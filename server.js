// nf-front: standalone XHTTP front, a self-hosted replacement for the
// Netlify edge front. No Netlify, Cloudflare, or Azion sits behind it:
// this server IS the front.
//
// Listens on PORT (default 8080, plain HTTP behind Caddy TLS).
// Only FRONT_PATH (default /nf-953693fb/) is forwarded: the backend is read
// per-request from the x-host header (host:port), the request is streamed
// to that backend over plain HTTP, and the response is streamed back.
// No auth of its own: the backend VLESS UUID is the auth.
'use strict';
const http = require('http');

const PORT = parseInt(process.env.PORT || '8080', 10);
const FRONT_PATH = process.env.FRONT_PATH || '/nf-953693fb/';
const FRONT_BASE = FRONT_PATH.endsWith('/') ? FRONT_PATH.slice(0, -1) : FRONT_PATH;

const HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'transfer-encoding', 'te', 'trailer',
  'proxy-authorization', 'proxy-authenticate', 'upgrade',
]);

function parseBackend(backend) {
  // host:port, [ipv6]:port, or bare host (default port 80)
  if (backend.startsWith('[')) {
    const end = backend.indexOf(']:');
    if (end === -1) return { host: backend, port: 80 };
    return { host: backend.slice(1, end), port: parseInt(backend.slice(end + 2), 10) || 80 };
  }
  const idx = backend.lastIndexOf(':');
  if (idx === -1) return { host: backend, port: 80 };
  return { host: backend.slice(0, idx), port: parseInt(backend.slice(idx + 1), 10) || 80 };
}

const server = http.createServer((req, res) => {
  let url;
  try {
    url = new URL(req.url, 'http://localhost');
  } catch {
    res.writeHead(400, { 'content-type': 'text/plain' });
    res.end('Bad request');
    return;
  }
  const path = url.pathname;
  if (path !== FRONT_BASE && !path.startsWith(FRONT_PATH)) {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('Not found');
    return;
  }
  const backend = req.headers['x-host'];
  if (!backend) {
    res.writeHead(400, { 'content-type': 'text/plain' });
    res.end('Missing x-host');
    return;
  }
  const { host, port } = parseBackend(backend);
  const headers = { ...req.headers };
  delete headers['x-host'];
  delete headers['host'];
  headers['host'] = backend;
  for (const h of HOP_BY_HOP) delete headers[h];

  const proxyReq = http.request(
    { host, port, path: url.pathname + url.search, method: req.method, headers },
    (proxyRes) => {
      const resHeaders = { ...proxyRes.headers };
      for (const h of HOP_BY_HOP) delete resHeaders[h];
      res.writeHead(proxyRes.statusCode, resHeaders);
      proxyRes.pipe(res);
    }
  );
  proxyReq.on('error', () => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'text/plain' });
      res.end('Upstream unreachable');
    } else {
      res.end();
    }
  });
  req.on('aborted', () => proxyReq.destroy());
  req.pipe(proxyReq);
});

// XHTTP download streams stay open; do not kill them with a request timeout.
server.requestTimeout = 0;
server.headersTimeout = 60000;
server.listen(PORT, '127.0.0.1', () => {
  console.log(`nf-front listening on 127.0.0.1:${PORT} path ${FRONT_PATH}`);
});
