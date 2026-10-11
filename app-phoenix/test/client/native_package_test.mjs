import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { auditPayload, auditDocument } from '../../scripts/native_package.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'native-package-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const put = (path, bytes = 'synthetic') => {
    mkdirSync(join(root, path, '..'), { recursive: true });
    writeFileSync(join(root, path), bytes);
  };
  for (const path of [
    'public/api-docs/swagger-ui-bundle.js', 'public/api-docs/swagger-ui.css',
    'swagger/v1/swagger.yaml', 'public/site.webmanifest',
    'public/maplibre/6.4.1/maplibre-gl.mjs', 'public/maplibre/6.4.1/maplibre-gl-worker.mjs',
    'public/maplibre/6.4.1/maplibre-gl-shared.mjs', 'vendor/poster_renderer/render.mjs',
    'vendor/poster_renderer/fonts/inter-400.ttf', 'tmp/phoenix/i18n.json',
    'tmp/phoenix/achievements.json', 'tmp/phoenix/time_zones.json',
    'release/priv/admin1_world.geojson', 'release/priv/countries.geojson.gz',
  ]) put(path);
  put('release/priv/static/native/app-abcd.js');
  put('release/priv/static/native/inter-font-abcd.css', '@font-face{src:url("./inter-abcd.woff2")}');
  put('release/priv/static/native/inter-abcd.woff2');
  put('release/priv/static/cache_manifest.json', JSON.stringify({ latest: {
    'native/app.js': 'native/app-abcd.js',
    'native/inter-font.css': 'native/inter-font-abcd.css',
    'native/inter.woff2': 'native/inter-abcd.woff2',
  }}));
  return { root, put, release: join(root, 'release/priv') };
}

test('native image payload requires runtime data renderer Swagger PWA and worker siblings', t => {
  const { root, release } = fixture(t);
  assert.ok(auditPayload(root, release).files > 10);
  rmSync(join(root, 'public/maplibre/6.4.1/maplibre-gl-shared.mjs'));
  assert.throws(() => auditPayload(root, release), /maplibre-gl-shared/);
});

test('native image payload rejects Rails discovery and missing digested font targets', t => {
  const { root, release, put } = fixture(t);
  assert.ok(auditPayload(root, release).digests === 3);
  put('config/sprockets-manifest.json');
  assert.throws(() => auditPayload(root, release), /forbidden/);
  rmSync(join(root, 'config/sprockets-manifest.json'));
  rmSync(join(root, 'release/priv/static/native/inter-abcd.woff2'));
  assert.throws(() => auditPayload(root, release), /inter-abcd.woff2/);
});

test('native document audit requires its entrypoint and refuses legacy discovery', () => {
  const document = '<html><script type="module" src="/native/app-abcd.js"></script></html>';
  assert.equal(auditDocument(document), true);
  for (const marker of ['<script type="importmap">{}</script>', 'data-controller="map"',
    '<turbo-frame id="frame">', '<script src="/assets/application.js"></script>']) {
    assert.throws(() => auditDocument(document + marker), /legacy/);
  }
  assert.throws(() => auditDocument('<html></html>'), /entrypoint/);
});

test('image smoke refuses existing network or volume before creating resources', async t => {
  const { spawnSync } = await import('node:child_process');
  const { chmodSync } = await import('node:fs');
  const root = mkdtempSync(join(tmpdir(), 'native-smoke-owner-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const docker = join(root, 'docker');
  writeFileSync(docker, `#!/bin/sh
printf '%s\\n' "$*" >>"$COMMANDS"
case "$*" in
  "--context colima $COLLISION inspect "*) exit 0;;
  *) exit 1;;
esac
`);
  chmodSync(docker, 0o755);
  for (const collision of ['network', 'volume']) {
    const commands = join(root, `${collision}.log`);
    const result = spawnSync('bash', ['app-phoenix/scripts/native_smoke.sh'], { env: {
      ...process.env, PATH: `${root}:${process.env.PATH}`, COLLISION: collision, COMMANDS: commands,
      NATIVE_DOCKER_CONTEXT: 'colima', NATIVE_IMAGE: 'synthetic-native', RAILS_FALLBACK_IMAGE: 'synthetic-rails',
      NATIVE_PLAYWRIGHT_ROOT: root, NATIVE_SMOKE_DATABASE: 'synthetic_database', NATIVE_SMOKE_OUT: join(root, 'out'), NATIVE_SMOKE_RUN: 'synthetic-test',
    }});
    assert.equal(result.status, 64, `${collision} collision refuses`);
    assert.doesNotMatch(readFileSync(commands, 'utf8'), /\b(create|run|rm)\b/, 'no resource mutation');
  }
});
