const http = require('http');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

const outputDir = process.env.AMBWEB_VEHICLE_IMAGE_DIR || 'F:\\AMBWeb\\assets\\images\\vehicles';
const port = Number(process.env.PORT || 3217);

function sanitizeModelName(value) {
  return String(value || 'vehicle').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 80) || 'vehicle';
}

function parseMultipart(buffer, boundary) {
  const body = buffer.toString('binary');
  const parts = body.split(`--${boundary}`);
  for (const part of parts) {
    if (!part.includes('Content-Disposition') || !part.includes('name="file"')) {
      continue;
    }

    const headerEnd = part.indexOf('\r\n\r\n');
    if (headerEnd < 0) {
      continue;
    }

    const binary = part.slice(headerEnd + 4).replace(/\r\n$/, '');
    return Buffer.from(binary, 'binary');
  }
  return null;
}

fs.mkdirSync(outputDir, { recursive: true });

const server = http.createServer((request, response) => {
  const requestUrl = new URL(request.url, `http://${request.headers.host || '127.0.0.1'}`);
  if (request.method !== 'POST' || requestUrl.pathname !== '/capture') {
    response.writeHead(404);
    response.end('Not found');
    return;
  }

  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', () => {
    const contentType = request.headers['content-type'] || '';
    const boundary = contentType.match(/boundary=(.+)$/)?.[1];
    const modelName = sanitizeModelName(requestUrl.searchParams.get('model'));

    if (!boundary) {
      response.writeHead(400);
      response.end('Missing multipart boundary');
      return;
    }

    const imageBuffer = parseMultipart(Buffer.concat(chunks), boundary);
    if (!imageBuffer) {
      response.writeHead(400);
      response.end('Missing screenshot file');
      return;
    }

    const outputPath = path.join(outputDir, `${modelName}.jpg`);
    fs.writeFileSync(outputPath, imageBuffer);
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ ok: true, model: modelName, path: outputPath }));
    console.log(`Saved ${modelName}.jpg`);
  });
});

server.listen(port, '127.0.0.1', () => {
  console.log(`Vehicle screenshot receiver listening at http://127.0.0.1:${port}/capture`);
  console.log(`Writing images to ${outputDir}`);
});
