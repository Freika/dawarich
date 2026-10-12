/**
 * Flatten a photo GeoJSON feature into the shape ReplayPhotoIndex expects:
 * the feature's properties (id, taken_at, thumbnail_url, ...) plus its geometry,
 * so ReplayManager.getCoordinates can extract coordinates from `geometry`.
 */
export function featureToPhoto(feature) {
  return { ...(feature.properties || {}), geometry: feature.geometry }
}
