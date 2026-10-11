import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { auditDocument } from './native_package.mjs';

const require = createRequire(join(process.env.NATIVE_PLAYWRIGHT_ROOT, 'package.json'));
const { chromium } = require('@playwright/test');
const baseURL = process.env.NATIVE_SMOKE_URL;
const fallback = process.env.NATIVE_SMOKE_MODE === 'rails';
const browser = await chromium.launch({ headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader'] });
const context = await browser.newContext({ baseURL, acceptDownloads: true,
  storageState: fallback ? process.env.NATIVE_SMOKE_SESSION : undefined });
const page = await context.newPage();
const assets = new Set();
const pending = [];
const failures = [];
const sockets = [];
const workers = [];
page.on('worker', worker => workers.push(worker.url()));
page.on('websocket', socket => sockets.push(socket.url().split('?')[0]));
page.on('response', response => {
  const url = new URL(response.url());
  if (url.origin !== new URL(baseURL).origin) return;
  if (/\.(js|mjs|css|woff2|png|svg)$/.test(url.pathname)) {
    assets.add(url.pathname);
    if (response.status() >= 400) failures.push(url.pathname);
    if (/\.(js|mjs)$/.test(url.pathname)) pending.push(response.text().then(body => {
      if (!fallback) assert.ok(!/Turbo\.session|@hotwired\/|application\.register\(/.test(body), 'bundled legacy runtime');
    }));
  }
});
function evidence(name) { console.log(`PASS ${name}`); }
async function document(path, connected = false) {
  const response = await page.goto(path, { waitUntil: 'domcontentloaded' });
  assert.equal(response.status(), 200, `document ${path}`);
  assert.equal(new URL(page.url()).pathname, path.split('?')[0], 'document destination');
  if (!fallback) auditDocument(await response.text());
  if (connected) await page.waitForSelector('[data-phx-main].phx-connected');
  evidence(`document ${path.split('?')[0]}`);
}
try {
  const health = await context.request.get('/api/v1/health');
  assert.equal(health.status(), 200);
  evidence('health');
  if (!fallback) {
    const refusal = await context.request.get('/missing-native-package-route');
    assert.equal(refusal.status(), 404);
    evidence('local missing-route refusal');
  }
  const points = await context.request.get('/api/v1/points?start_at=2025-10-15&end_at=2025-10-16', { headers: { Authorization: `Bearer ${process.env.NATIVE_SMOKE_API_KEY}` } });
  assert.equal(points.status(), 200);
  assert.ok((await points.json()).length >= 3);
  evidence('synthetic points API');
  if (!fallback) {
    await document('/');
    await document('/users/password/new');
    await document('/users/sign_in');
    await page.locator('[name="user[email]"]').fill('demo@dawarich.app');
    await page.locator('[name="user[password]"]').fill('safepassword');
    await page.locator('form[action="/users/sign_in"] [type="submit"]').click();
    await page.waitForURL(/\/map/);
    await page.evaluate(() => localStorage.setItem('dawarich_onboarding_shown', 'true'));
  }
  for (const path of ['/tags', '/imports/new', '/users/edit', '/settings/general', '/settings/users'])
    await document(path, !fallback);
  if (!fallback) {
    await document('/tags/new', true);
    await page.locator('[data-emoji-toggle]').click();
    await page.waitForSelector('em-emoji-picker');
    evidence('lazy emoji picker');
    await document('/stats', true);
    await page.waitForSelector('[data-chart-plot] canvas');
    evidence('lazy chart');
    await document('/trips/new', true);
    await page.waitForFunction(() => [...document.querySelectorAll('trix-editor')].some(e => !!e.editor));
    evidence('lazy editor');
    await document('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59', true);
    await page.waitForSelector('.maplibregl-canvas');
    await page.locator('[data-testid="map-button-poster"]').first().click();
    await page.waitForSelector('#native-poster-dialog[open] .maplibregl-canvas');
    await page.locator('[data-poster-layout]').selectOption('social-ig-square');
    const downloadPromise = page.waitForEvent('download', { timeout: 120000 });
    await page.locator('[data-poster-download]').click();
    const download = await downloadPromise;
    const bytes = readFileSync(await download.path());
    assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.ok(bytes.length > 1000);
    assert.equal(bytes.readUInt32BE(16), 1080);
    assert.equal(bytes.readUInt32BE(20), 1080);
    evidence('synthetic studio PNG export');
    await page.locator('#native-poster-dialog [data-poster-switch-video]').click();
    await page.waitForSelector('#native-video-dialog[open] .maplibregl-canvas');
    evidence('lazy video studio');
    await document('/s/00000000-0000-4000-8000-000000000004');
    await page.waitForSelector('.maplibregl-canvas');
    evidence('public map');
    assert.ok(sockets.some(url => url.endsWith('/live/websocket')), 'LiveView websocket');
    const globals = await page.evaluate(() => ['Turbo', 'Stimulus', 'Application'].filter(key => !!window[key]));
    assert.deepEqual(globals, []);
    await context.storageState({ path: process.env.NATIVE_SMOKE_SESSION });
    evidence('native session saved privately for whole-app fallback');
  } else evidence('native session accepted by whole-app Rails fallback');
  const manifestResponse = await context.request.get('/site.webmanifest');
  assert.equal(manifestResponse.status(), 200);
  const manifest = await manifestResponse.json();
  for (const icon of manifest.icons) assert.equal((await context.request.get(icon.src)).status(), 200);
  for (const path of ['/api-docs', '/api-docs/swagger-ui-bundle.js',
    '/api-docs/swagger-ui.css', '/api-docs/v1/swagger.yaml', '/maplibre/6.4.1/maplibre-gl-worker.mjs',
    '/maplibre/6.4.1/maplibre-gl-shared.mjs']) {
    const response = await context.request.get(path);
    assert.equal(response.status(), 200, `asset ${path}`);
    assert.ok((await response.body()).length > 0);
  }
  evidence('Swagger PWA icons worker siblings');
  await page.evaluate(() => document.fonts.ready);
  await Promise.all(pending);
  assert.deepEqual(failures, [], 'local asset responses');
  if (!fallback) {
    assert.ok([...assets].some(path => path.endsWith('.woff2')), 'native fonts fetched');
    assert.ok(workers.some(path => path.includes('maplibre-gl-worker')), 'map worker started');
  }
  writeFileSync(process.env.NATIVE_SMOKE_RECEIPT, JSON.stringify({ mode: fallback ? 'rails' : 'native',
    assets: [...assets].sort(), workers: workers.length, sockets: sockets.length, status: 'passed' }, null, 2));
  evidence('asset and socket receipt');
} finally {
  await context.close();
  await browser.close();
}
