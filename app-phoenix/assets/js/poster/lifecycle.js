import { createLifecycle } from "../map/runtime/lifecycle.js"
import { createBackdrop } from "./backdrop.js"
import { layoutById } from "./data/layouts.js"
import { resolveTheme } from "./data/theme_loader.js"
import { createPreviewMap, fitFrame, trackBounds } from "./preview.js"
import { drawOverlay } from "./render/overlay.js"
import {
  fontFamily,
  initialPosterState,
  posterText,
  withLoadedData,
} from "./state.js"
import { createRestyle, posterStyle, seedTokens } from "./style.js"

const closed = () => new DOMException("Poster studio closed", "AbortError")
const RESTYLE_KEYS = ["hidden", "opacity", "width"]
const REDRAW_KEYS = ["title", "subtitle", "coords", "textEnabled", "fontKey"]

export function createPosterLifecycle({
  elements,
  poster,
  loadLibrary,
  loadThemeTokens,
  loadFonts,
  label = () => "",
  trim = (coords) => coords,
  window: win = globalThis.window,
  URL: urls = globalThis.URL,
  timers = globalThis,
  onChange = () => {},
  onError = () => {},
}) {
  let state = initialPosterState()
  let tokens = null
  let session = null
  let generation = 0
  const backdrop = createBackdrop(elements.backdrop, { URL: urls })
  const restyle = createRestyle({ timers, apply: () => applyStyle() })

  const check = (current) => {
    if (current !== generation || !session) throw closed()
  }

  async function open({ themeKey }) {
    if (session) return
    const current = ++generation
    const controller = new AbortController()
    const lifetime = createLifecycle()
    session = { controller, lifetime, map: null }
    elements.dialog.showModal()
    const onResize = () => resizeFrame()
    win.addEventListener("resize", onResize)
    lifetime.own(() => win.removeEventListener("resize", onResize))
    try {
      if (!tokens)
        await setTheme(themeKey, { signal: controller.signal, current })
      const data = await poster.load({ signal: controller.signal })
      check(current)
      state = withLoadedData(state, data, label(data))
      resizeFrame()
      await loadFonts({ signal: controller.signal })
      check(current)
      const library = await loadLibrary()
      check(current)
      createMap(library)
      onChange(state)
    } catch (error) {
      if (current !== generation) return
      dispose()
      if (error?.name !== "AbortError") onError("open_failed", error)
    }
  }

  function dispose() {
    if (!session) return
    generation++
    const { controller, lifetime } = session
    session = null
    controller.abort()
    restyle.cancel()
    lifetime.destroy()
    backdrop.release()
  }

  function close() {
    dispose()
    if (elements.dialog.open) elements.dialog.close()
  }

  async function applyRange(range) {
    if (!session || state.rangeLoading) return
    const current = generation
    state = { ...state, rangeLoading: true }
    onChange(state)
    try {
      const data = await poster.applyDates(range, {
        signal: session.controller.signal,
      })
      check(current)
      state = withLoadedData(state, data, label(data))
      applyStyle()
      recenter()
    } finally {
      if (current === generation) {
        state = { ...state, rangeLoading: false }
        onChange(state)
      }
    }
  }

  function exportRequest() {
    const map = session?.map
    if (!map || !tokens) return null
    const bounds = map.getBounds()
    return {
      style: posterStyle(state, tokens),
      bounds: [
        [bounds.getWest(), bounds.getSouth()],
        [bounds.getEast(), bounds.getNorth()],
      ],
      layout: layoutById(state.layoutId),
      dpi: state.dpi,
      format: state.format,
      theme: resolveTheme(tokens),
      text: posterText(state, map.getCenter()),
      font: fontFamily(state),
      cssSize: {
        width: elements.frame.clientWidth,
        height: elements.frame.clientHeight,
      },
      title: state.title,
    }
  }

  function recenter() {
    const bounds =
      trackBounds(state.data?.geojson, trim) ?? poster.fallbackBounds()
    if (bounds) session?.map?.fitBounds(bounds, { padding: 24 })
  }

  function createMap(library) {
    const bounds =
      trackBounds(state.data.geojson, trim) ?? poster.fallbackBounds()
    const map = createPreviewMap(library, {
      container: elements.map,
      style: posterStyle(state, tokens),
      bounds,
    })
    session.map = map
    session.lifetime.own(() => map.remove())
    map.on("move", () => redraw())
    map.on("moveend", () => onChange(state))
    map.on("idle", () => backdrop.update(map.getCanvas()))
    map.once("load", () => {
      redraw()
      onChange(state)
    })
  }

  async function setTheme(key, { signal, current = generation } = {}) {
    const raw = await loadThemeTokens(key, { signal })
    check(current)
    tokens = seedTokens(raw)
    state = { ...state, themeKey: key }
    restyle.schedule()
    onChange(state)
  }

  function setToken(name, value) {
    tokens = { ...tokens, [name]: value }
    restyle.schedule()
  }

  function update(patch) {
    state = { ...state, ...patch }
    const keys = Object.keys(patch)
    if (keys.includes("layoutId")) resizeFrame()
    if (keys.some((key) => RESTYLE_KEYS.includes(key))) restyle.schedule()
    if (keys.some((key) => REDRAW_KEYS.includes(key))) redraw()
    onChange(state)
  }

  function applyStyle() {
    session?.map?.setStyle(posterStyle(state, tokens))
    redraw()
  }

  function resizeFrame() {
    const layout = layoutById(state.layoutId)
    const { width, height } = fitFrame(elements.stage, layout.aspect, {
      getComputedStyle: (element) => win.getComputedStyle(element),
    })
    elements.frame.style.width = `${width}px`
    elements.frame.style.height = `${height}px`
    session?.map?.resize()
    redraw()
  }

  function redraw() {
    if (!tokens || !elements.overlay) return
    const canvas = elements.overlay
    const ratio = win.devicePixelRatio || 1
    canvas.width = Math.round(elements.frame.clientWidth * ratio)
    canvas.height = Math.round(elements.frame.clientHeight * ratio)
    canvas.getContext("2d").clearRect(0, 0, canvas.width, canvas.height)
    drawOverlay(canvas, {
      theme: resolveTheme(tokens),
      ...posterText(state, session?.map?.getCenter()),
      font: fontFamily(state),
    })
  }

  return {
    open,
    close,
    recenter,
    applyRange,
    exportRequest,
    update,
    setTheme: (key) => setTheme(key),
    setToken,
    redraw,
    resizeFrame,
    applyStyle,
    get state() {
      return state
    },
    get tokens() {
      return tokens
    },
    get map() {
      return session?.map ?? null
    },
    get session() {
      return session
    },
    replaceData(data) {
      state = withLoadedData(state, data, label(data))
    },
    destroy: close,
  }
}
