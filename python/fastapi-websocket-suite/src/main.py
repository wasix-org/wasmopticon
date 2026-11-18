from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse

app = FastAPI(title="FastAPI WebSocket Echo")

ROOT_HTML = r"""
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>WebSocket Echo</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bulma@1.0.2/css/bulma.min.css" />
    <style>
      /* Let messages expand the page; keep them compact */
      .messages .message { margin: .25rem 0; }
      .messages .message-body { padding: .4rem .5rem; font-size: 0.9rem; }
      .meta { color: #6b7280; font-size: 0.8rem; margin-left: .5rem; }
      .is-mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
      /* Status size handled by Bulma classes now */
    </style>
  </head>
  <body>
    <section class="section">
      <div class="container">
        <h1 class="title">WebSocket Echo</h1>

        <p class="is-size-4">This is an example Python fastapi Websocket server running on <a href="https://wasmer.io/products/edge">Wasmer Edge</a>.</p>
        <p class="is-size-4">The WebSocket echo server will echo back any message you send to it.</p>
        <p class="mt-2 mb-2">
          <a class="button is-light is-medium" href="https://github.com/wasmer-examples/python-fastapi-websockets" target="_blank" rel="noopener noreferrer">
            <span class="icon is-medium" aria-hidden="true">
              <img src="https://cdn.jsdelivr.net/gh/devicons/devicon/icons/github/github-original.svg" alt="GitHub" style="width: 24px; height: 24px;">
            </span>
            <span>Check out the code on GitHub</span>
          </a>
        </p>

        <div class="box">
          <div class="is-flex is-align-items-center is-justify-content-space-between">
            <div>
              <span class="mr-2">Status:</span>
              <span id="status" class="tag is-warning is-medium">Connecting…</span>
            </div>
            <div>
              <button id="reconnect" class="button is-small is-light" disabled>Reconnect</button>
            </div>
          </div>
        </div>

        <div class="field has-addons">
          <div class="control is-expanded">
            <input id="input" class="input" type="text" placeholder="Type a message and press Enter" value="Hello Wasmer!" />
          </div>
          <div class="control">
            <button id="send" class="button is-primary">Send</button>
          </div>
        </div>

        <div class="box messages" id="messages">
          <p id="placeholder" class="has-text-grey">Send messages</p>
        </div>
      </div>
    </section>

    <script>
      const statusEl = document.getElementById('status');
      const inputEl = document.getElementById('input');
      const sendBtn = document.getElementById('send');
      const reconnectBtn = document.getElementById('reconnect');
      const messagesEl = document.getElementById('messages');
      const wsProtocol = location.protocol === 'https:' ? 'wss' : 'ws';
      const wsUrl = `${wsProtocol}://${location.host}/api/ws`;
      let ws = null;

      function formatTime(d) {
        return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
      }

      // type: 'sent' | 'received'
      function clearPlaceholder() {
        const ph = document.getElementById('placeholder');
        if (ph) ph.remove();
      }

      function addMessage(text, type, extraMeta = '') {
        clearPlaceholder();
        const article = document.createElement('article');
        article.className = `message ${type === 'sent' ? 'is-primary' : 'is-info'}`;
        const body = document.createElement('div');
        body.className = 'message-body';

        const now = new Date();
        const meta = document.createElement('span');
        meta.className = 'meta';
        meta.textContent = `(${formatTime(now)}${extraMeta ? ` • ${extraMeta}` : ''})`;

        const content = document.createElement('span');
        content.className = 'is-mono';
        content.textContent = text;

        body.appendChild(content);
        body.appendChild(meta);
        article.appendChild(body);
        // Prepend newest messages at the top
        messagesEl.insertBefore(article, messagesEl.firstChild);
      }

      function setStatus(state) {
        statusEl.classList.remove('is-warning', 'is-success', 'is-danger');
        if (state === 'connected') {
          statusEl.textContent = 'Connected';
          statusEl.classList.add('is-success');
          reconnectBtn.disabled = true;
        } else if (state === 'connecting') {
          statusEl.textContent = 'Connecting…';
          statusEl.classList.add('is-warning');
          reconnectBtn.disabled = true;
        } else {
          statusEl.textContent = 'Disconnected';
          statusEl.classList.add('is-danger');
          reconnectBtn.disabled = false;
        }
      }

      const inflight = new Map(); // id -> send timestamp
      let nextId = 1;

      function connect() {
        setStatus('connecting');
        ws = new WebSocket(wsUrl);
        ws.addEventListener('open', () => setStatus('connected'));
        ws.addEventListener('close', () => setStatus('disconnected'));
        ws.addEventListener('message', (event) => {
          let data = event.data;
          // Expect echo format: "<id>|<payload>" to measure RTT if applicable
          const sep = data.indexOf('|');
          if (sep > 0) {
            const idStr = data.slice(0, sep);
            const payload = data.slice(sep + 1);
            const t0 = inflight.get(idStr);
            let meta = '';
            if (t0) {
              const rttMs = Math.round(performance.now() - t0);
              inflight.delete(idStr);
              meta = `RTT ${rttMs} ms`;
            }
            addMessage(`Received: ${payload}`, 'received', meta);
          } else {
            addMessage(`Received: ${data}`, 'received');
          }
        });
      }

      connect();

      const MAX_LEN = 500;

      function sendCurrent() {
        const msg = inputEl.value;
        if (!msg) return;
        if (msg.length > MAX_LEN) {
          addMessage(`Cannot send: message exceeds ${MAX_LEN} chars`, 'received');
          return;
        }
        if (ws && ws.readyState === WebSocket.OPEN) {
          const id = String(nextId++);
          inflight.set(id, performance.now());
          ws.send(`${id}|${msg}`);
          addMessage(`Sent: ${msg}`, 'sent');
        } else {
          addMessage('Cannot send: WebSocket not connected', 'received');
        }
        inputEl.value = '';
        inputEl.focus();
      }

      sendBtn.addEventListener('click', sendCurrent);
      inputEl.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
          sendCurrent();
        }
      });
      reconnectBtn.addEventListener('click', () => {
        if (!ws || ws.readyState !== WebSocket.OPEN) connect();
      });
    </script>
  </body>
  </html>
"""


@app.get("/", response_class=HTMLResponse, include_in_schema=False)
async def root() -> str:
    return ROOT_HTML


@app.websocket("/api/ws")
async def websocket_endpoint(websocket: WebSocket):
    MAX_LEN = 500
    await websocket.accept()
    try:
        while True:
            data = await websocket.receive_text()
            # Enforce max length of 500 characters on server as well
            if len(data) > MAX_LEN:
                data = data[:MAX_LEN]
            # Echo back exactly what was sent so client can measure RTT
            await websocket.send_text(data)
    except Exception:
        # Connection closed or errored; exit gracefully
        pass


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
