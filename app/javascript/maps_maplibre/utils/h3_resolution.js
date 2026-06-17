export const ZOOM_TO_RES = [
  { maxZoom: 3, res: 3 },
  { maxZoom: 5, res: 4 },
  { maxZoom: 7, res: 5 },
  { maxZoom: 9, res: 6 },
  { maxZoom: 11, res: 7 },
  { maxZoom: 13, res: 8 },
  { maxZoom: Infinity, res: 9 },
]

export function resolutionForZoom(zoom) {
  for (const entry of ZOOM_TO_RES) {
    if (zoom <= entry.maxZoom) return entry.res
  }
  return 9
}
