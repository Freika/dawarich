import { createHash } from 'node:crypto';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const required = [
  'public/api-docs/swagger-ui-bundle.js', 'public/api-docs/swagger-ui.css',
  'swagger/v1/swagger.yaml', 'public/site.webmanifest',
  'public/maplibre/6.4.1/maplibre-gl.mjs', 'public/maplibre/6.4.1/maplibre-gl-worker.mjs',
  'public/maplibre/6.4.1/maplibre-gl-shared.mjs', 'vendor/poster_renderer/render.mjs',
  'vendor/poster_renderer/fonts/inter-400.ttf', 'tmp/phoenix/i18n.json',
  'tmp/phoenix/achievements.json', 'tmp/phoenix/time_zones.json',
];
const forbidden = [
  'Gemfile', 'Gemfile.lock', 'bin/rails', 'app/javascript', 'vendor/javascript',
  'config/importmap.rb', 'config/sprockets-manifest.json', 'public/assets',
  'tmp/phoenix/importmap.json', 'app/controllers', 'vendor/bundle',
];
function present(path) {
  if (!existsSync(path) || !statSync(path).isFile() || statSync(path).size === 0)
    throw new Error(`missing payload: ${path}`);
}
export function auditPayload(root, priv) {
  for (const path of forbidden)
    if (existsSync(join(root, path))) throw new Error(`forbidden payload: ${path}`);
  for (const path of required) present(join(root, path));
  for (const path of ['admin1_world.geojson', 'countries.geojson.gz']) present(join(priv, path));
  const staticRoot = join(priv, 'static');
  const manifest = JSON.parse(readFileSync(join(staticRoot, 'cache_manifest.json')));
  if (!manifest.latest?.['native/app.js']) throw new Error('missing native entrypoint digest');
  for (const target of Object.values(manifest.latest)) {
    const path = resolve(staticRoot, target);
    if (!path.startsWith(resolve(staticRoot) + '/')) throw new Error('digest escapes static root');
    present(path);
    const expected = manifest.digests?.[target]?.sha512;
    const actual = createHash('sha512').update(readFileSync(path)).digest('base64');
    if (!expected || expected !== actual) throw new Error(`digest integrity mismatch: ${target}`);
    if (path.endsWith('.css')) {
      const css = readFileSync(path, 'utf8');
      for (const match of css.matchAll(/url\(\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^)'"\s]+))\s*\)/g)) {
        const reference = match[1] ?? match[2] ?? match[3];
        if (/^(data:|https?:|#)/.test(reference)) continue;
        const relative = path.slice(resolve(staticRoot).length).replaceAll('\\', '/');
        const url = new URL(reference, `http://static.test${relative}`);
        present(join(staticRoot, decodeURIComponent(url.pathname)));
      }
    }
  }
  return { files: required.length + 2, digests: Object.keys(manifest.latest).length };
}
export function auditDocument(html) {
  if (/type=["']importmap|data-controller=|<turbo-|\/assets\/application|data-turbo-/i.test(html))
    throw new Error('legacy frontend discovery');
  if (!/src=["']\/native\/(?:app|auth_http|public_charts)(?:-[a-f0-9]+)?\.js/.test(html))
    throw new Error('missing native entrypoint');
  return true;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href)
  console.log(JSON.stringify(auditPayload(process.argv[2], process.argv[3])));
