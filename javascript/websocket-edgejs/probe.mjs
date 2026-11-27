import assert from "node:assert/strict";
import { once } from "node:events";

const port = process.argv[2];
assert.match(port, /^[1-9][0-9]{0,4}$/);
const endpoint = `ws://127.0.0.1:${port}/ws`;
const sockets = [];

function nextEvent(socket, name) {
  return once(socket, name, { signal: AbortSignal.timeout(8000) }).catch((error) => {
    throw new Error(`WebSocket did not emit ${name}`, { cause: error });
  });
}

async function connect() {
  const socket = new WebSocket(endpoint);
  socket.binaryType = "arraybuffer";
  sockets.push(socket);
  await nextEvent(socket, "open");
  return socket;
}

async function exchange(socket, payload) {
  const message = nextEvent(socket, "message");
  socket.send(payload);
  const [reply] = await message;
  return reply.data;
}

async function closeFromServer(socket) {
  const closed = nextEvent(socket, "close");
  socket.send("close from server");
  const [event] = await closed;
  assert.equal(event.code, 4001);
  assert.equal(event.reason, "fixture complete");
  assert.equal(event.wasClean, true);
}

try {
  const socket = await connect();
  const text = "echo € 🧪";
  assert.equal(await exchange(socket, text), text);
  console.log("PASS text echo preserves UTF-8 and frame type");

  const binary = Buffer.from([0, 255, 13, 10, 128, 127, 192, 1]);
  const reply = await exchange(socket, binary);
  assert.ok(reply instanceof ArrayBuffer);
  assert.deepEqual(Buffer.from(reply), binary);
  console.log("PASS binary echo preserves every byte and frame type");

  await closeFromServer(socket);
  console.log("PASS server-initiated close delivers the code and reason");

  const peers = await Promise.all(Array.from({ length: 10 }, () => connect()));
  assert.ok(peers.every((peer) => peer.readyState === WebSocket.OPEN));
  await Promise.all(peers.map(async (peer, index) => {
    const payload = `parallel socket ${index + 1}`;
    assert.equal(await exchange(peer, payload), payload);
  }));
  await Promise.all(peers.map(closeFromServer));
  console.log("PASS 10 concurrent sockets each echoed their own text and closed cleanly");
} finally {
  for (const socket of sockets) {
    if (socket.readyState < WebSocket.CLOSING) socket.close();
  }
}
