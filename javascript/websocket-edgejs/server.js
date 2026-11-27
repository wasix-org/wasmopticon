import { createServer } from "node:http";
import { WebSocketServer } from "ws";

const host = process.env.HOST || "127.0.0.1";
const port = Number(process.env.PORT || 8080);

const server = createServer((request, response) => {
  const ready = request.method === "GET" && request.url === "/";
  response.writeHead(ready ? 200 : 404, {
    "Content-Type": "text/plain; charset=utf-8",
    "X-Fixture": "websocket-edgejs",
  });
  response.end(ready ? "WebSocket fixture ready" : "Not Found");
});

const websocket = new WebSocketServer({
  server,
  path: "/ws",
  maxPayload: 64 * 1024,
});

websocket.on("connection", (socket) => {
  socket.on("error", (error) => console.error(error));
  socket.on("message", (data, isBinary) => {
    if (!isBinary && data.toString() === "close from server") {
      socket.close(4001, "fixture complete");
      return;
    }
    socket.send(data, { binary: isBinary });
  });
});

server.listen(port, host);
