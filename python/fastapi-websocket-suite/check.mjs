import assert from "node:assert/strict";
import { once } from "node:events";

const url = new URL(process.argv[2]);
const home = await fetch(url, { signal: AbortSignal.timeout(5000) });
assert.equal(home.status, 200);
const html = await home.text();
assert.match(html, /<title>WebSocket Echo<\/title>/);
assert.match(html, /\/api\/ws/);

const wsUrl = new URL("/api/ws", url);
wsUrl.protocol = "ws:";

async function echo(messages) {
  const socket = new WebSocket(wsUrl);
  const options = { signal: AbortSignal.timeout(5000) };
  try {
    await once(socket, "open", options);
    for (const message of messages) {
      const reply = once(socket, "message", options);
      socket.send(message);
      const [event] = await reply;
      assert.equal(event.data, message);
    }
    const closed = once(socket, "close", options);
    socket.close(1000);
    const [event] = await closed;
    assert.equal(event.code, 1000);
    assert.equal(event.wasClean, true);
  } finally {
    socket.close();
  }
}

await echo(["1|Hello Wasmer", '{"message":"雪"}']);
await echo(["2|I reconnected"]);
console.log("WebSocket upgrade, three exact text echoes, clean close and reconnect passed");
