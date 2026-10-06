import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"
import vm from "node:vm"

const stripImports = (source) =>
  source
    .replace(/^import[\s\S]*?from "[^"]+"\n/gm, "")
    .replace(/^import "[^"]+"\n/gm, "")
const source = (name) =>
  readFile(
    new URL(`../../priv/static/js/hooks/${name}.js`, import.meta.url),
    "utf8",
  )

class Hub {
  constructor() {
    this.listeners = new Map()
  }
  addEventListener(type, callback) {
    const set = this.listeners.get(type) ?? new Set()
    set.add(callback)
    this.listeners.set(type, set)
  }
  removeEventListener(type, callback) {
    this.listeners.get(type)?.delete(callback)
  }
  dispatchEvent(event) {
    return Promise.all(
      [...(this.listeners.get(event.type) ?? [])].map((callback) =>
        callback(event),
      ),
    )
  }
  count() {
    return [...this.listeners.values()].reduce((n, set) => n + set.size, 0)
  }
}
function node(dataset = {}) {
  const el = new Hub()
  const classes = new Set(["hidden"])
  Object.assign(el, {
    dataset,
    value: "",
    textContent: "",
    style: {},
    disabled: false,
    attrs: {},
    classList: {
      contains: (s) => classes.has(s),
      add: (s) => classes.add(s),
      remove: (s) => classes.delete(s),
      toggle(s, force) {
        if (force) classes.add(s)
        else classes.delete(s)
      },
    },
    setAttribute(key, value) {
      this.attrs[key] = value
    },
    removeAttribute(key) {
      delete this.attrs[key]
    },
    getAttribute(key) {
      return this.attrs[key]
    },
    querySelectorAll() {
      return []
    },
    getBoundingClientRect() {
      return { width: 600, height: 800 }
    },
    closest() {
      return this
    },
    append() {},
    replaceChildren() {},
    pause() {},
    getContext() {
      return { clearRect() {} }
    },
  })
  return el
}
async function controlsRuntime() {
  const document = new Hub()
  const window = new Hub()
  document.documentElement = { lang: "en" }
  document.activeElement = null
  const el = node()
  const input = node({
    setting: "units",
    action: "change->video-studio#updateSetting",
  })
  input.type = "select-one"
  input.value = "mi"
  const globals = {
    document,
    window,
    console,
    defaultSettings: () => ({
      theme: "terracotta",
      units: "km",
      duration_sec: 15,
      track_color: "#0088ff",
      fog_color: "#000000",
      fog_opacity: 65,
      visualization_mode: "route",
      format: "portrait",
      hud_scale: 100,
      track_width: 120,
    }),
    formatFor: () => ({ width: 1080, height: 1920 }),
  }
  const context = vm.createContext(globals)
  vm.runInContext(
    stripImports(await source("video_studio_controls")).replace(
      /export /g,
      "",
    ) + "\nglobalThis.controlsAPI = {bindControls, controls}",
    context,
  )
  const studio = {
    element: el,
    settings: globals.defaultSettings(),
    themeSwatchTargets: [],
    visualizationModeTargets: [],
    formatOptionTargets: [],
    settingsChanged() {
      this.syncControls()
    },
    resizeFrame() {},
  }
  Object.assign(studio, globals.controlsAPI.controls)
  el.querySelectorAll = () => [input]
  el.contains = (other) => other === input
  studio.close = () => el.classList.add("hidden")
  studio.open = async () => el.classList.remove("hidden")
  studio.restoreSettings = async (event) => {
    studio.restored = JSON.parse(event.currentTarget.dataset.settings)
  }
  return {
    studio,
    document,
    window,
    el,
    input,
    context,
    globals,
    ...globals.controlsAPI,
  }
}

test("R08: native studio controls and lifecycle matches current Rails contract without a native-owner Rails effect", async () => {
  const r = await controlsRuntime()
  const unbind = r.bindControls(r.studio)
  r.el.dispatchEvent({ type: "change", target: r.input, preventDefault() {} })
  assert.equal(r.studio.settings.units, "mi")
  const checkbox = node({ setting: "watermark" })
  checkbox.type = "checkbox"
  checkbox.checked = false
  r.studio.updateSetting({ currentTarget: checkbox })
  assert.equal(r.studio.settings.watermark, false)
  const slider = node({ setting: "fog_opacity" })
  slider.type = "range"
  slider.value = "45"
  r.studio.updateSetting({ currentTarget: slider })
  assert.equal(r.studio.settings.fog_opacity, 45)
  r.studio.selectTheme({ currentTarget: node({ themeKey: "noir" }) })
  assert.equal(r.studio.settings.theme, "noir")
  r.studio.selectFormat({ currentTarget: node({ format: "landscape" }) })
  assert.equal(r.studio.settings.format, "landscape")
  r.document.dispatchEvent({ type: "video-studio:open", detail: {} })
  await Promise.resolve()
  assert.equal(r.el.classList.contains("hidden"), false)
  const card = node({
    action: "video-studio#restoreSettings",
    settings: '{"source":"trip","end_at":"2026-10-03T09:00:00Z"}',
  })
  await r.document.dispatchEvent({
    type: "click",
    target: card,
    preventDefault() {},
  })
  await Promise.resolve()
  assert.equal(r.studio.restored.source, "trip")
  unbind()
  unbind()
  assert.equal(
    r.el.count() + r.document.count() + r.window.count(),
    0,
    "all delegated listeners are removed",
  )
  const reconnect = r.bindControls(r.studio)
  assert.equal(r.document.listeners.get("video-studio:open").size, 1)
  reconnect()
  assert.equal(r.document.count(), 0)
  for (const [file, name] of [
    ["video_studio_dates", "dates"],
    ["video_studio_preview", "preview"],
    ["video_studio_render", "rendering"],
    ["video_studio_save", "saving"],
  ]) {
    vm.runInContext(
      stripImports(await source(file)).replace(/export /g, "") +
        `\nglobalThis.${name} = ${name}`,
      r.context,
    )
  }
  r.globals.controls = r.controls
  r.globals.bindControls = r.bindControls
  r.globals.URL = { revokeObjectURL() {} }
  const targetNodes = new Map()
  r.el.dataset = { videoStudioFontsValue: "{}" }
  r.el.querySelector = (selector) => {
    if (!targetNodes.has(selector)) targetNodes.set(selector, node())
    return targetNodes.get(selector)
  }
  r.el.querySelectorAll = () => []
  vm.runInContext(
    stripImports(await source("video_studio")).replace(/export /g, "") +
      "\nglobalThis.hookAPI = {mountVideoStudio, destroyVideoStudio}",
    r.context,
  )
  const studio = r.globals.hookAPI.mountVideoStudio(r.el, {})
  assert.equal(
    r.globals.hookAPI.mountVideoStudio(r.el, {}),
    studio,
    "repeated native mounts reuse one studio",
  )
  const beforeDestroy = studio.operationVersion
  r.globals.hookAPI.destroyVideoStudio(r.el)
  r.globals.hookAPI.destroyVideoStudio(r.el)
  assert.ok(studio.operationVersion > beforeDestroy)
  assert.equal(studio.disposed, true)
  assert.equal(r.el.count() + r.document.count() + r.window.count(), 0)
})

test("R09: native rendering and download bridge matches current Rails contract without a native-owner Rails effect", async () => {
  const urls = [],
    revoked = []
  const document = { activeElement: null }
  const context = vm.createContext({
    document,
    window: {},
    console,
    AbortController,
    URL: {
      createObjectURL() {
        const url = `blob:${urls.length}`
        urls.push(url)
        return url
      },
      revokeObjectURL(url) {
        revoked.push(url)
      },
    },
    translate: (key) => key,
    formatFor: () => ({ width: 1920, height: 1080 }),
    DAWARICH_URL: "https://dawarich.app",
    isVideoExportSupported: () => true,
    renderRouteVideo: async ({ onProgress, signal }) => {
      onProgress(1, 2)
      assert.equal(signal.aborted, false)
      return { blob: { size: 64 } }
    },
  })
  const code = stripImports(await source("video_studio_render"))
    .replace(/export /g, "")
    .replace(
      'const { renderRouteVideo } = await import("video_studio/video_renderer")',
      "",
    )
  vm.runInContext(code + "\nglobalThis.renderAPI = rendering", context)
  const studio = {
    style: {},
    points: [1, 2],
    settings: {
      duration_sec: 15,
      format: "landscape",
      hud_scale: 100,
      watermark: true,
      fog_opacity: 65,
    },
    resultTarget: node(),
    saveButtonTarget: node(),
    cancelButtonTarget: node(),
    renderButtonTarget: node(),
    progressBarTarget: node(),
    statusTarget: node(),
    hasRenderButtonTarget: true,
    hasOverlayTarget: false,
    drawHudPreview() {},
    hudLabels() {
      return {}
    },
    operationVersion: 1,
    destroyed: false,
    operationIsCurrent(value) {
      return value === this.operationVersion && !this.destroyed
    },
    startOperation() {
      return ++this.operationVersion
    },
  }
  Object.assign(studio, context.renderAPI)
  await studio.render()
  assert.equal(studio.resultTarget.src, "blob:0")
  assert.equal(studio.blob.size, 64)
  assert.equal(studio.saveButtonTarget.disabled, false)
  assert.equal(studio.progressBarTarget.attrs["aria-valuenow"], "50")
  assert.equal(studio.rendering, false)
  studio.teardown()
  assert.deepEqual(
    revoked,
    ["blob:0"],
    "destroy revokes the rendered object URL",
  )
  assert.equal(studio.blob, null)
  studio.points = []
  await studio.render()
  assert.equal(studio.statusTarget.textContent, "video.empty_track")
  studio.abortController = new AbortController()
  studio.cancel()
  assert.equal(studio.abortController.signal.aborted, true)
})

test("R06: studio recipe and native hooks matches current Rails contract without a native-owner Rails effect", async () => {
  const uploads = [],
    posted = [],
    progress = []
  const xhr = {
    upload: new Hub(),
    aborts: 0,
    abort() {
      this.aborts++
    },
  }
  const globals = {
    console,
    FormData,
    File,
    AbortController,
    DOMException,
    document: {
      querySelector() {
        return { content: "synthetic-csrf" }
      },
    },
    DirectUpload: class {
      constructor(file, url, delegate) {
        uploads.push({ file, url })
        this.delegate = delegate
      }
      create(callback) {
        this.delegate.directUploadWillStoreFileWithXHR(xhr)
        xhr.upload.dispatchEvent({
          type: "progress",
          lengthComputable: true,
          loaded: 1,
          total: 2,
        })
        callback(null, { signed_id: "synthetic-signed-id" })
      }
    },
    async fetch(url, request) {
      posted.push({ url, request })
      return {
        ok: true,
        text: async () =>
          '<turbo-stream action="prepend" target="route-video-gallery-list"></turbo-stream>',
      }
    },
  }
  const context = vm.createContext(globals)
  const code = await readFile(
    new URL(
      "../../../app/javascript/video_studio/save_video.js",
      import.meta.url,
    ),
    "utf8",
  )
  vm.runInContext(
    stripImports(code).replace(/export /g, "") +
      "\nglobalThis.saveAPI = saveVideo",
    context,
  )
  const signal = new AbortController().signal
  const recipe = {
    source: "map",
    start_at: "2026-10-03T08:00:00Z",
    end_at: "2026-10-03T09:00:00Z",
    track_color: "#aa33cc",
    fog_opacity: 65,
    show_route: false,
  }
  const stream = await globals.saveAPI({
    blob: new Blob(["synthetic-mp4"]),
    name: "Route",
    settings: recipe,
    uploadUrl: "/rails/active_storage/direct_uploads",
    createUrl: "/route_videos",
    signal,
    onProgress: (ratio) => progress.push(ratio),
  })
  assert.equal(
    posted[0].request.body.get("route_video[settings][end_at]"),
    recipe.end_at,
  )
  assert.equal(
    posted[0].request.body.get("route_video[settings][start_at]"),
    recipe.start_at,
  )
  assert.equal(
    posted[0].request.body.get("route_video[settings][show_route]"),
    "false",
  )
  assert.equal(
    posted[0].request.body.get("route_video[file]"),
    "synthetic-signed-id",
  )
  assert.equal(posted[0].request.headers["X-CSRF-Token"], "synthetic-csrf")
  assert.equal(
    posted[0].request.signal,
    signal,
    "save carries the studio abort signal",
  )
  assert.deepEqual(progress, [0.5])
  assert.equal(
    xhr.upload.count(),
    0,
    "upload progress listener is detached after completion",
  )
  assert.ok(stream.includes("turbo-stream"))
  const aborted = new AbortController()
  aborted.abort()
  await assert.rejects(
    globals.saveAPI({
      blob: new Blob(["synthetic"]),
      name: "Route",
      settings: recipe,
      signal: aborted.signal,
    }),
    /abort|cancel/i,
  )
  assert.equal(posted.length, 1)
})
