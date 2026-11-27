const { createServer } = require("node:http");
const { Queue, Worker } = require("bullmq");
const Redis = require("ioredis");

const queueName = "wasmopticon-redis";
const port = Number(process.env.PORT || 18394);
const host = process.env.HOST || "127.0.0.1";
const redisOptions = {
  host: process.env.REDIS_HOST || "127.0.0.1",
  port: Number(process.env.REDIS_PORT || 18395),
  connectTimeout: 5_000,
  maxRetriesPerRequest: 1,
};

function send(response, status, body) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(body));
}

async function readJob(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const job = JSON.parse(Buffer.concat(chunks).toString());
  if (!job || typeof job.id !== "string" || !/^[a-z][a-z0-9-]{0,31}$/.test(job.id) ||
      !Array.isArray(job.values) || !job.values.length || job.values.length > 20 ||
      !job.values.every((value) => Number.isSafeInteger(value) && Math.abs(value) <= 1_000_000)) {
    throw new SyntaxError("Expected an ID and 1–20 small integers");
  }
  return job;
}

async function main() {
  const redis = new Redis(redisOptions);
  const queue = new Queue(queueName, { connection: redis });
  const worker = new Worker(queueName, async (job) => ({
    id: job.id,
    sum: job.data.values.reduce((total, value) => total + value, 0),
  }), { connection: { ...redisOptions, maxRetriesPerRequest: null } });
  for (const emitter of [redis, queue, worker]) {
    emitter.on("error", (error) => { console.error(error); });
  }
  await Promise.all([queue.waitUntilReady(), worker.waitUntilReady()]);

  const server = createServer(async (request, response) => {
    try {
      const path = new URL(request.url, "http://fixture.invalid").pathname;
      if (request.method === "GET" && path === "/") {
        await redis.ping();
        return send(response, 200, { queue: queueName, worker: "ready" });
      }
      if (request.method === "POST" && path === "/jobs") {
        const { id, values } = await readJob(request);
        const job = await queue.add("sum", { values }, { jobId: id });
        return send(response, 202, { id: job.id });
      }
      const match = /^\/jobs\/([a-z][a-z0-9-]{0,31})$/.exec(path);
      if (request.method === "GET" && match) {
        const job = await queue.getJob(match[1]);
        if (!job) return send(response, 404, { error: "Job not found" });
        if (job.failedReason) return send(response, 200, { id: job.id, state: "failed" });
        if (job.finishedOn) {
          return send(response, 200, { id: job.id, state: "completed", result: job.returnvalue });
        }
        return send(response, 200, { id: job.id, state: "pending" });
      }
      send(response, 404, { error: "Route not found" });
    } catch (error) {
      if (error instanceof SyntaxError) return send(response, 400, { error: error.message });
      console.error(error);
      send(response, 500, { error: "Queue operation failed" });
    }
  });

  const shutdown = () => {
    server.close(async () => {
      try {
        await worker.close();
        await queue.close();
        await redis.quit();
      } catch (error) {
        console.error(error);
        process.exitCode = 1;
      }
    });
  };
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
  server.listen(port, host, () => {
    console.log(`BullMQ fixture listening on http://${host}:${port}`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
