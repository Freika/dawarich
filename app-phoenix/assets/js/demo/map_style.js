const TILE_SOURCE_URL = "https://tyles.dwri.xyz/planet/{z}/{x}/{y}.mvt"
const ATTRIBUTION =
  '<a href="https://github.com/protomaps/basemaps">Protomaps</a> © <a href="https://openstreetmap.org">OpenStreetMap</a>'

function currentTheme() {
  const root = document.documentElement
  return root.getAttribute("data-theme")?.includes("dark") ||
    root.classList.contains("dark")
    ? "dark"
    : "light"
}

export async function demoStyle(theme = currentTheme(), fetchImpl = fetch) {
  const response = await fetchImpl(`/maps_maplibre/styles/${theme}.json`)
  const style = await response.json()
  if (style.sources?.protomaps) {
    style.sources.protomaps = {
      type: "vector",
      tiles: [TILE_SOURCE_URL],
      minzoom: 0,
      maxzoom: 15,
      attribution: style.sources.protomaps.attribution || ATTRIBUTION,
    }
  }
  return style
}
