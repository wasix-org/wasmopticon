const assert = require("node:assert/strict");
const { once } = require("node:events");
const path = require("node:path");
const { Worker, isMainThread, threadId } = require("node:worker_threads");

async function main() {
  assert.equal(isMainThread, true);
  assert.equal(threadId, 0);
  const input = { limit: 100_000, label: "parent" };
  globalThis.workerProbe = "parent";

  const worker = new Worker(path.join(__dirname, "worker.cjs"), { workerData: input });
  const workerThread = worker.threadId;
  assert.ok(workerThread > 0);

  let result;
  worker.once("message", (message) => { result = message; });
  const [exitCode] = await once(worker, "exit");
  assert.equal(exitCode, 0);
  assert.deepEqual(result, {
    count: 9592,
    sum: 454396537,
    isMainThread: false,
    threadId: workerThread,
    globalWasUnset: true,
    label: "worker",
  });
  assert.equal(input.label, "parent");
  assert.equal(globalThis.workerProbe, "parent");
  console.log(JSON.stringify({ primes: result.count, sum: result.sum, isolated: true, exitCode }));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
