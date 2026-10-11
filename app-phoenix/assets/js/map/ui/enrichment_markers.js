export function createEnrichmentMarkers({
  map,
  library,
  document,
  onAdjust,
  onFocus,
}) {
  const markers = new Map()
  const position = (row) => {
    const current = markers.get(row.immich_asset_id)?.marker.getLngLat()
    return {
      latitude: current?.lat ?? Number(row.latitude),
      longitude: current?.lng ?? Number(row.longitude),
    }
  }
  function clear() {
    for (const owned of markers.values()) {
      owned.active = false
      owned.marker.off("dragend", owned.drag)
      owned.element.removeEventListener("click", owned.focus)
      owned.marker.remove()
    }
    markers.clear()
  }
  function replace(rows) {
    clear()
    if (!library?.Marker || !document) return
    for (const row of rows) {
      const coordinates = position(row)
      if (
        !Number.isFinite(coordinates.latitude) ||
        !Number.isFinite(coordinates.longitude)
      )
        continue
      const element = document.createElement("div")
      element.className =
        "flex items-center justify-center w-8 h-8 rounded-full border-2 border-white shadow-md cursor-grab text-xs"
      element.title = row.filename ?? row.immich_asset_id
      const marker = new library.Marker({ element, draggable: true })
        .setLngLat([coordinates.longitude, coordinates.latitude])
        .addTo(map)
      const owned = { marker, element, row, active: true }
      owned.drag = () => {
        if (owned.active) onAdjust?.(row, position(row))
      }
      owned.focus = (event) => {
        event.stopPropagation?.()
        if (owned.active) onFocus?.(row, position(row))
      }
      marker.on("dragend", owned.drag)
      element.addEventListener("click", owned.focus)
      markers.set(row.immich_asset_id, owned)
    }
  }
  function update(selected, busy) {
    const ids = new Set(selected.map((row) => row.immich_asset_id))
    for (const { marker, element, row } of markers.values()) {
      const checked = ids.has(row.immich_asset_id)
      const delta = row.time_delta_seconds ?? 0
      element.style.background = checked
        ? delta < 300
          ? "#22c55e"
          : delta < 900
            ? "#eab308"
            : "#f97316"
        : "#9ca3af"
      element.style.opacity = checked ? "1" : "0.6"
      element.textContent = checked ? "📷✓" : "📷"
      marker.setDraggable(!busy)
    }
  }
  return { position, replace, update, clear }
}
