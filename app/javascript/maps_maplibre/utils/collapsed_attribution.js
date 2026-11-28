import * as maplibregl from "maplibre-gl"

// MapLibre opens a compact attribution the first time it has text to show.
// Collapse it at that moment so every map starts with only the (i) button;
// a reader who opens it keeps it open.
// ponytail: wraps the private _updateCompact; recheck on a MapLibre upgrade.
export function collapsedAttributionControl() {
  const control = new maplibregl.AttributionControl({ compact: true })
  const updateCompact = control._updateCompact
  control._updateCompact = () => {
    const wasCompact =
      control._container?.classList.contains("maplibregl-compact")
    updateCompact()
    if (!wasCompact) control._updateCompactMinimize()
  }
  return control
}
