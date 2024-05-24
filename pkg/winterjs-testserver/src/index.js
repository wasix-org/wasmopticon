async function handler(request) {
  const url = new URL(request.url);

  let path = url.pathname;
  if (path.startsWith("http://") || path.startsWith("https://")) {
    path = path.replace(/^https?:\/\//, "");
    // Remove the domain.
    const index = path.indexOf("/");
    if (index >= 0) {
      path = path.slice(index);
    }
  }
  // Strip leading slashes
  path = path.replace(/^\/+/, "");

  const parts = path.split("/");

  if (parts.length === 0) {
    return new Response("WinterJS testserver - use an available test route");
  }

  const route = parts[0];
  const rest = parts.slice(1);
  switch (route) {
    case 'http-proxy':
      return handlerHttpProxy(request, rest);

    default:
      return new Response(`unknown route '${route}'`, { status: 400 });
  }
}

async function handlerHttpProxy(req, parts) {
  const url = parts.join("/");

  console.log({parts});
  try {
    new URL(url);
  } catch (e) {
    console.log('Invalid URL: ' + e);
    return new Response(`Invalid URL: '${url}'`, { status: 400 });
  }

  console.log('proxying http request', {
    url,
    headers: Object.fromEntries(req.headers),
    method: req.method,
  });
  const response = await fetch(url, {
    headers: req.headers,
    body: req.body,
    method: req.method,
  });
  console.log('received response', {
    status: response.status,
    headers: Object.fromEntries(response.headers),
  });

  return response;
}

addEventListener("fetch", (fetchEvent) => {
  fetchEvent.respondWith(handler(fetchEvent.request));
});
