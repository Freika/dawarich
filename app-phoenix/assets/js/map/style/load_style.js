import { applyMapStyle } from "./map_style.js"

export async function fetchStyle(config, { signal }) {
  const response = await fetch(
    config.styleUrl ?? "/maps_maplibre/styles/light.json",
    { signal, credentials: "same-origin" },
  )
  if (!response.ok) throw new Error("Map style unavailable")
  return applyMapStyle(await response.json(), config)
}
