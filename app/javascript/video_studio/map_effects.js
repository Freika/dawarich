// Canvas effects shared by the live studio preview and the exported video.
// MapLibre projects into CSS pixels while both canvases can be rendered at a
// higher pixel ratio, so every projected point is scaled into the target.

function canvasPoint(map, coordinate, width, height) {
  if (!map || !coordinate) return null

  const projected = map.project(coordinate)
  const mapCanvas = map.getCanvas?.()
  const container = map.getContainer?.()
  const cssWidth = mapCanvas?.clientWidth || container?.clientWidth || width
  const cssHeight = mapCanvas?.clientHeight || container?.clientHeight || height

  return {
    x: projected.x * (width / cssWidth),
    y: projected.y * (height / cssHeight),
  }
}

function fogFill(color, opacity) {
  const match = /^#([0-9a-f]{6})$/i.exec(color || "")
  const rgb = match
    ? [0, 2, 4].map((index) =>
        Number.parseInt(match[1].slice(index, index + 2), 16),
      )
    : [0, 0, 0]
  return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${opacity})`
}

export function drawFogOverlay(
  ctx,
  {
    map,
    features = [],
    head = null,
    width,
    height,
    opacity = 0.65,
    color = "#000000",
  },
) {
  ctx.clearRect(0, 0, width, height)
  if (opacity <= 0) return

  ctx.save()
  ctx.fillStyle = fogFill(color, Math.min(1, Math.max(0, opacity)))
  ctx.fillRect(0, 0, width, height)

  // Erase a broad, round-ended corridor from the fog. Keeping the reveal
  // proportional to the short edge makes it read consistently in every
  // format and at both preview and export resolution.
  const revealWidth = Math.min(width, height) * 0.055
  ctx.globalCompositeOperation = "destination-out"
  ctx.strokeStyle = "#000000"
  ctx.fillStyle = "#000000"
  ctx.lineWidth = revealWidth
  ctx.lineCap = "round"
  ctx.lineJoin = "round"

  for (const feature of features) {
    const coordinates = feature?.geometry?.coordinates
    if (feature?.geometry?.type !== "LineString" || !coordinates?.length)
      continue

    ctx.beginPath()
    let started = false
    for (const coordinate of coordinates) {
      const point = canvasPoint(map, coordinate, width, height)
      if (!point) continue
      if (started) ctx.lineTo(point.x, point.y)
      else {
        ctx.moveTo(point.x, point.y)
        started = true
      }
    }
    if (started) ctx.stroke()
  }

  // At the intro frame there is no line yet, but the starting location has
  // already been explored. The circle also rounds the current reveal edge.
  const headPoint = canvasPoint(map, head, width, height)
  if (headPoint) {
    ctx.beginPath()
    ctx.arc(headPoint.x, headPoint.y, revealWidth / 2, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.restore()
}

export function drawRouteMarker(
  ctx,
  { map, coordinate, width, height, accent = "#2563EB" },
) {
  const point = canvasPoint(map, coordinate, width, height)
  if (!point) return

  const unit = Math.min(width, height) / 100
  ctx.save()
  ctx.fillStyle = "#ffffff"
  ctx.beginPath()
  ctx.arc(point.x, point.y, unit * 1.65, 0, Math.PI * 2)
  ctx.fill()
  ctx.fillStyle = accent
  ctx.beginPath()
  ctx.arc(point.x, point.y, unit * 1.05, 0, Math.PI * 2)
  ctx.fill()
  ctx.restore()
}
