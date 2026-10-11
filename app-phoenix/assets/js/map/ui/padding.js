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

export function panelPadding({ container, overlay, notice }) {
  return () => {
    const mapRect = container?.getBoundingClientRect()
    const padding = overlayAwarePadding(
      mapRect,
      overlay()?.getBoundingClientRect(),
    )
    const rect = notice?.()?.getBoundingClientRect()
    if (
      mapRect &&
      rect &&
      rect.left < mapRect.right &&
      rect.right > mapRect.left &&
      rect.top < mapRect.bottom &&
      rect.bottom > mapRect.top
    ) {
      padding.bottom = Math.max(
        padding.bottom,
        Math.ceil(mapRect.bottom - rect.top + OVERLAY_GAP),
      )
    }
    return padding
  }
}
