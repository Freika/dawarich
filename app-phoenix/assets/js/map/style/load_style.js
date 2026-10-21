import { mapNotify } from "../ui/notify.js"
import { classifyBasemapUrl, styleDocumentFailed } from "./basemap_url.js"
import { composeRasterFallback, composeVectorFallback } from "./fallback.js"
import { applyMapStyle } from "./map_style.js"

const names = new Set(["dark", "light", "white", "black", "grayscale"])
function absolute(value, base) {
  if (!value || !base || value.startsWith("/")) return value
  return new URL(value, base).href.replaceAll("%7B", "{").replaceAll("%7D", "}")
}
function assets(style, base) {
  const result = structuredClone(style)
  result.glyphs = absolute(result.glyphs, base)
  if (typeof result.sprite === "string")
    result.sprite = absolute(result.sprite, base)
  for (const source of Object.values(result.sources ?? {})) {
    if (source.url) source.url = absolute(source.url, base)
    if (source.tiles)
      source.tiles = source.tiles.map((url) => absolute(url, base))
  }
  return result
}

export async function fetchStyle(
  config,
  { signal, fetch = globalThis.fetch } = {},
) {
  const type = classifyBasemapUrl(config.tilesUrl)
  const styleName = names.has(config.styleName) ? config.styleName : "light"
  const localUrl = config.styleUrl ?? `/maps_maplibre/styles/${styleName}.json`
  const read = async (url) => {
    const response = await fetch(url, {
      signal,
      credentials: url.startsWith("/") ? "same-origin" : "omit",
    })
    if (!response.ok) throw new Error("Map style unavailable")
    const style = await response.json()
    if (signal?.aborted) throw signal.reason
    return assets(
      style,
      url.startsWith("/")
        ? new URL(url, globalThis.location?.origin ?? "http://localhost").href
        : url,
    )
  }
  if (type === "style") {
    try {
      return await read(config.tilesUrl)
    } catch (error) {
      if (signal?.aborted) throw error
      mapNotify(() => config)("error", "settings.custom_style_load_failed")
      return applyMapStyle(await read("/maps_maplibre/styles/light.json"), {
        ...config,
        styleName: "light",
        tilesUrl: null,
      })
    }
  }
  const overlay = config.tilesFallback && type
  let base
  try {
    base = await read(localUrl)
  } catch (error) {
    if (signal?.aborted || localUrl === "/maps_maplibre/styles/light.json")
      throw error
    base = await read("/maps_maplibre/styles/light.json")
  }
  if (type === "raster" && !overlay)
    return {
      version: 8,
      glyphs: base.glyphs,
      sprite: base.sprite,
      sources: {
        protomaps: {
          type: "raster",
          tiles: [config.tilesUrl],
          tileSize: 256,
          attribution: "",
        },
      },
      layers: [
        {
          id: "background",
          type: "background",
          paint: { "background-color": "#e0e0e0" },
        },
        { id: "basemap-raster", type: "raster", source: "protomaps" },
      ],
    }
  const style = applyMapStyle(base, {
    ...config,
    tilesUrl: overlay ? null : config.tilesUrl,
  })
  return overlay
    ? (type === "raster" ? composeRasterFallback : composeVectorFallback)(
        style,
        config.tilesUrl,
      )
    : style
}

export function installStyleFallback({ map, getConfig, load = fetchStyle }) {
  let destroyed = false,
    active = null,
    generation = 0
  const failed = async (event) => {
    const config = getConfig()
    if (
      destroyed ||
      active ||
      classifyBasemapUrl(config.tilesUrl) !== "style" ||
      !styleDocumentFailed(event, config.tilesUrl)
    )
      return
    const current = ++generation
    active = new AbortController()
    try {
      const style = await load(
        {
          ...config,
          tilesUrl: null,
          styleName: "light",
          styleUrl: "/maps_maplibre/styles/light.json",
        },
        { signal: active.signal },
      )
      if (
        !destroyed &&
        generation === current &&
        getConfig().tilesUrl === config.tilesUrl
      )
        map.setStyle(style)
    } catch {
    } finally {
      if (generation === current) active = null
    }
  }
  map.on("error", failed)
  return {
    destroy() {
      destroyed = true
      generation++
      active?.abort()
      active = null
      map.off("error", failed)
    },
  }
}
