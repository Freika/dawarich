export const DEFAULT_ROUTE_COLOR = "#FF3B30"
export const DEFAULT_CASING_COLOR = "#000000"

export const THEME_KEYS = [
  "autumn",
  "blueprint",
  "contrast_zones",
  "copper_patina",
  "emerald",
  "forest",
  "gradient_roads",
  "japanese_ink",
  "midnight_blue",
  "monochrome_blue",
  "neon_cyberpunk",
  "noir",
  "ocean",
  "pastel_dream",
  "sunset",
  "terracotta",
  "warm_beige",
]

function parseHex(hex) {
  const match = /^#([0-9a-f]{6})$/i.exec(hex || "")
  if (!match) return null
  return [0, 2, 4].map((i) => Number.parseInt(match[1].slice(i, i + 2), 16))
}

function mixHex(from, to, ratio) {
  const a = parseHex(from)
  const b = parseHex(to)
  if (!a || !b) return from
  const mixed = a.map((v, i) => Math.round(v + (b[i] - v) * ratio))
  return `#${mixed.map((v) => v.toString(16).padStart(2, "0")).join("")}`
}

export function extendTokens(tokens) {
  const contrast = tokens.text ?? "#808080"
  return {
    buildings: tokens.buildings ?? mixHex(tokens.bg, contrast, 0.08),
    railway: tokens.railway ?? tokens.road_default,
    boundaries: tokens.boundaries ?? mixHex(tokens.bg, contrast, 0.3),
  }
}

export function resolveTheme(tokens) {
  return {
    name: tokens.name ?? "",
    description: tokens.description ?? "",
    bg: tokens.bg,
    text: tokens.text,
    gradientColor: tokens.gradient_color ?? tokens.bg,
    water: tokens.water,
    parks: tokens.parks,
    ...extendTokens(tokens),
    roads: {
      motorway: tokens.road_motorway,
      primary: tokens.road_primary,
      secondary: tokens.road_secondary,
      tertiary: tokens.road_tertiary,
      residential: tokens.road_residential,
      default: tokens.road_default,
    },
    route: tokens.route ?? DEFAULT_ROUTE_COLOR,
    casing: tokens.bg ?? DEFAULT_CASING_COLOR,
  }
}

const cache = new Map()
const tokenCache = new Map()

export async function loadThemeTokens(
  key,
  { fetch = globalThis.fetch, signal } = {},
) {
  if (tokenCache.has(key)) return tokenCache.get(key)
  const response = await fetch(`/poster_themes/${key}.json`, { signal })
  if (!response.ok) {
    throw new Error(`Failed to load poster theme "${key}" (${response.status})`)
  }
  const tokens = await response.json()
  tokenCache.set(key, tokens)
  return tokens
}

export async function loadTheme(key, options = {}) {
  if (cache.has(key)) return cache.get(key)
  const resolved = resolveTheme(await loadThemeTokens(key, options))
  cache.set(key, resolved)
  return resolved
}
