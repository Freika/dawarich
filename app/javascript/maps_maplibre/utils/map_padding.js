const BASE_MAP_PADDING = 50
const OVERLAY_GAP = 12

export function overlayAwarePadding(mapRect, overlayRect) {
  const padding = {
    top: BASE_MAP_PADDING,
    right: BASE_MAP_PADDING,
    bottom: BASE_MAP_PADDING,
    left: BASE_MAP_PADDING,
  }

  if (!mapRect || !overlayRect) return padding

  const overlapsLeftEdge =
    overlayRect.left < mapRect.right && overlayRect.right > mapRect.left
  if (!overlapsLeftEdge) return padding

  padding.left = Math.max(
    padding.left,
    Math.ceil(overlayRect.right - mapRect.left + OVERLAY_GAP),
  )

  return padding
}
