import { cancelled } from "../map/data/request_scope.js"

export const HUD_MONO_FAMILY = "Video HUD Mono"
export const HUD_SANS_FAMILY = "Video HUD Sans"

const FACES = [
  { family: HUD_MONO_FAMILY, key: "jetbrains-mono", weight: "400" },
  { family: HUD_MONO_FAMILY, key: "jetbrains-mono", weight: "700" },
  { family: HUD_SANS_FAMILY, key: "inter", weight: "400" },
  { family: HUD_SANS_FAMILY, key: "inter", weight: "700" },
]

const FALLBACK = { mono: "monospace", sans: "sans-serif" }
const LOAD_TIMEOUT_MS = 3000
const cache = new Map()

function loadFonts(urls, { FontFace: Face, fonts, timers }) {
  if (!urls || typeof Face !== "function" || !fonts)
    return Promise.resolve(FALLBACK)
  const key = JSON.stringify(Object.entries(urls).sort())
  if (cache.has(key)) return cache.get(key)

  const loading = (async () => {
    const loads = FACES.map(async ({ family, key: name, weight }) => {
      const url = urls[`${name}-${weight}`]
      if (!url) return
      const face = new Face(family, `url(${url})`, { weight })
      fonts.add(await face.load())
    })
    let timer
    const timeout = new Promise((resolve) => {
      timer = timers.setTimeout(() => resolve(false), LOAD_TIMEOUT_MS)
    })
    const loaded = await Promise.race([
      Promise.all(loads).then(() => true),
      timeout,
    ])
      .catch(() => false)
      .finally(() => timers.clearTimeout(timer))
    return loaded ? { mono: HUD_MONO_FAMILY, sans: HUD_SANS_FAMILY } : FALLBACK
  })()
  cache.set(key, loading)
  return loading
}

export function ensureHudFonts(
  urls,
  {
    signal,
    FontFace = globalThis.FontFace,
    fonts = globalThis.document?.fonts,
    timers = globalThis,
  } = {},
) {
  if (signal?.aborted) return Promise.reject(cancelled())
  const loading = loadFonts(urls, { FontFace, fonts, timers })
  if (!signal) return loading
  return new Promise((resolve, reject) => {
    const abort = () => reject(cancelled())
    signal.addEventListener("abort", abort, { once: true })
    loading
      .then(resolve, reject)
      .finally(() => signal.removeEventListener("abort", abort))
  })
}
