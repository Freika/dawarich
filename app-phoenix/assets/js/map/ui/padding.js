export function overlayAwarePadding(mapRect, overlayRect) {
  const padding = {
    top: 50,
    right: 50,
    bottom: 50,
    left: 50,
  }
  if (
    !mapRect ||
    !overlayRect ||
    overlayRect.bottom <= mapRect.top ||
    overlayRect.top >= mapRect.bottom ||
    overlayRect.left >= mapRect.right ||
    overlayRect.right <= mapRect.left
  )
    return padding
  padding.left = Math.max(
    padding.left,
    Math.ceil(overlayRect.right - mapRect.left + 12),
  )
  return padding
}

export function panelPadding({ container, overlay }) {
  return () =>
    overlayAwarePadding(
      container?.getBoundingClientRect(),
      overlay()?.getBoundingClientRect(),
    )
}
