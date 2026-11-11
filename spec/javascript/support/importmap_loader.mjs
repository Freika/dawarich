// Resolves the bare specifiers from config/importmap.rb so tests can import
// the real modules. Runs through NODE_OPTIONS because CI is on Node 18.17,
// which has no module.register.
const root = new URL("../../../", import.meta.url)
const appJavascript = new URL("app/javascript/", root)
const vendorJavascript = new URL("vendor/javascript/", root)

const APP_TREES = [
  "maps_maplibre/",
  "controllers/",
  "services/",
  "poster_studio/",
  "video_studio/",
  "achievements/",
  "channels/",
]
const VENDORED = ["fflate", "h3-js", "pmtiles", "mp4-muxer", "emoji-mart"]
const STUBS = {
  "maplibre-gl": "maplibre_gl.mjs",
  "@hotwired/stimulus": "stimulus.mjs",
  "@hotwired/stimulus-loading": "stimulus_loading.mjs",
  "@rails/actioncable": "actioncable.mjs",
  "@rails/activestorage": "activestorage.mjs",
}

const asModule = (url) => ({
  url: url.href,
  format: "module",
  shortCircuit: true,
})

export async function resolve(specifier, context, nextResolve) {
  if (STUBS[specifier]) {
    return asModule(new URL(`stubs/${STUBS[specifier]}`, import.meta.url))
  }
  if (specifier === "i18n") return asModule(new URL("i18n.js", appJavascript))
  if (VENDORED.includes(specifier)) {
    return asModule(new URL(`${specifier}.js`, vendorJavascript))
  }
  if (APP_TREES.some((tree) => specifier.startsWith(tree))) {
    const file = specifier.endsWith(".js") ? specifier : `${specifier}.js`
    return asModule(new URL(file, appJavascript))
  }

  if (
    specifier.startsWith(".") &&
    !specifier.endsWith(".js") &&
    context.parentURL?.startsWith(appJavascript.href)
  ) {
    return asModule(new URL(`${specifier}.js`, context.parentURL))
  }

  const resolved = await nextResolve(specifier, context)
  const isBrowserModule =
    resolved.url.startsWith(appJavascript.href) ||
    resolved.url.startsWith(vendorJavascript.href)
  return isBrowserModule ? { ...resolved, format: "module" } : resolved
}
