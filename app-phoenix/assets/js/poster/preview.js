export function createPreviewMap(library, { container, style, bounds }) {
  const map = new library.Map({
    container,
    style,
    ...(bounds
      ? { bounds, fitBoundsOptions: { padding: 24, animate: false } }
      : { center: [0, 0], zoom: 1 }),
    attributionControl: false,
    fadeDuration: 0,
    dragRotate: false,
    pitchWithRotate: false,
    preserveDrawingBuffer: true,
  })
  map.touchZoomRotate.disableRotation()
  map.keyboard.disableRotation()
  return map
}

export function collectCoords(geojson) {
  const coords = []
  for (const feature of geojson?.features ?? []) {
    const geometry = feature.geometry
    if (!geometry) continue
    if (geometry.type === "LineString") coords.push(...geometry.coordinates)
    else if (geometry.type === "MultiLineString")
      for (const line of geometry.coordinates) coords.push(...line)
    else if (geometry.type === "Point") coords.push(geometry.coordinates)
  }
  return coords
}

export function trackBounds(geojson, trim = (coords) => coords) {
  const coords = collectCoords(geojson)
  if (coords.length === 0) return null

  const kept = trim(coords)
  let [minLng, minLat] = kept[0]
  let [maxLng, maxLat] = kept[0]
  for (const [lng, lat] of kept) {
    if (lng < minLng) minLng = lng
    if (lng > maxLng) maxLng = lng
    if (lat < minLat) minLat = lat
    if (lat > maxLat) maxLat = lat
  }
  if (minLng === maxLng && minLat === maxLat) {
    return [
      [minLng - 0.01, minLat - 0.01],
      [maxLng + 0.01, maxLat + 0.01],
    ]
  }
  return [
    [minLng, minLat],
    [maxLng, maxLat],
  ]
}

export function fitFrame(
  stage,
  aspect,
  { getComputedStyle = globalThis.getComputedStyle } = {},
) {
  const styles = getComputedStyle(stage)
  const controlsHeight = [...stage.children]
    .filter(
      (el) =>
        !("posterFrame" in (el.dataset ?? {})) &&
        !("posterBackdrop" in (el.dataset ?? {})),
    )
    .reduce((sum, el) => {
      const childStyles = getComputedStyle(el)
      return (
        sum +
        el.offsetHeight +
        Number.parseFloat(childStyles.marginTop) +
        Number.parseFloat(childStyles.marginBottom)
      )
    }, 0)

  const maxWidth =
    (stage.clientWidth -
      Number.parseFloat(styles.paddingLeft) -
      Number.parseFloat(styles.paddingRight)) *
    0.9
  const maxHeight =
    (stage.clientHeight -
      Number.parseFloat(styles.paddingTop) -
      Number.parseFloat(styles.paddingBottom) -
      controlsHeight) *
    0.96
  let width = maxWidth
  let height = width / aspect
  if (height > maxHeight) {
    height = maxHeight
    width = height * aspect
  }
  return { width: Math.round(width), height: Math.round(height) }
}
