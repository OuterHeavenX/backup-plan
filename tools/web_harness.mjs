// Runs a web export in headless Chromium and streams the engine console.
// usage: node web_harness.mjs <serve_dir> <timeout_ms> <stop_regex> [screenshot.png]
// Exits 0 when a console line matched <stop_regex>, 1 on timeout.
import { chromium } from 'playwright';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const [dir, timeoutMs, stopRe, shot] = process.argv.slice(2);
const mime = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const f = path.join(dir, u === '/' ? 'index.html' : u);
  if (!fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const port = server.address().port;
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1152, height: 648 } });
let done = false;
const re = new RegExp(stopRe);
page.on('console', m => { const t = m.text(); console.log('[console] ' + t); if (re.test(t)) done = true; });
page.on('pageerror', e => console.log('[pageerror] ' + e.message));
await page.goto(`http://127.0.0.1:${port}/index.html`);
const t0 = Date.now();
while (!done && Date.now() - t0 < Number(timeoutMs)) await page.waitForTimeout(500);
if (shot) await page.screenshot({ path: shot });
await browser.close();
server.close();
console.log(done ? 'HARNESS: stopped on match' : 'HARNESS: timeout');
process.exit(done ? 0 : 1);
