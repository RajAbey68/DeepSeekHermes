const http = require('http');
const https = require('https');

const PORT = parseInt(process.env.PORT || '8080', 10);
const API_KEY = process.env.DEEPSEEK_API_KEY;

if (!API_KEY) {
  console.error('DEEPSEEK_API_KEY env var is required');
  process.exit(1);
}

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
};

const server = http.createServer((req, res) => {
  Object.entries(CORS).forEach(([k, v]) => res.setHeader(k, v));

  if (req.method === 'OPTIONS') {
    res.writeHead(204).end();
    return;
  }

  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  if (req.method !== 'POST' || !req.url.endsWith('/chat/completions')) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: 'Not found', url: req.url }));
    return;
  }

  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Invalid JSON' }));
      return;
    }

    // Accept both "deepseek/deepseek-chat" and "deepseek-chat"
    if (typeof payload.model === 'string' && payload.model.includes('/')) {
      payload.model = payload.model.split('/').pop();
    }

    const bodyOut = JSON.stringify(payload);
    const upstream = https.request(
      {
        hostname: 'api.deepseek.com',
        port: 443,
        path: '/chat/completions',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${API_KEY}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(bodyOut),
        },
      },
      (upRes) => {
        const headers = { ...upRes.headers, ...CORS };
        delete headers['transfer-encoding'];
        res.writeHead(upRes.statusCode || 502, headers);
        upRes.pipe(res);
      }
    );

    upstream.on('error', (err) => {
      console.error('Upstream error:', err.message);
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Upstream error', message: err.message }));
      }
    });

    upstream.write(bodyOut);
    upstream.end();
  });
});

server.listen(PORT, () => {
  console.log(`Gateway listening on :${PORT}`);
});
