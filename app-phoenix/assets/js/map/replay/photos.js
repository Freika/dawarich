import { createPhotoMarker } from "../ui/photo_marker.js"
import { ReplayPhotoIndex } from "./photo_index.js"
import { ReplayPhotoStack } from "./photo_stack.js"

export function normalizeReplayPhotos(photos) {
  return (photos ?? []).map((photo) => ({
    ...photo,
    taken_at: photo.taken_at ?? photo.capturedAt ?? photo.localDateTime,
    filename: photo.filename ?? photo.originalFileName,
  }))
}

export function createReplayPhotos({
  photos,
  map,
  library,
  reader,
  document,
  container,
  manager,
  labels,
}) {
  const index = new ReplayPhotoIndex({
    photos: normalizeReplayPhotos(photos),
    timezone: manager.timezone,
    getCoordinates: (photo) => manager.getCoordinates(photo),
  })
  const stack = container
    ? new ReplayPhotoStack({
        container,
        map,
        library,
        reader,
        document,
        labels,
        timezone: manager.timezone,
      })
    : null
  const markers = new Map()
  let destroyed = false
  function sync(point) {
    if (destroyed || !point) return
    const stamp = manager.getTimestamp(point)
    const ms =
      typeof stamp === "number"
        ? stamp < 10000000000
          ? stamp * 1000
          : stamp
        : new Date(stamp).getTime()
    const revealed = index.revealedPhotos(manager.getCurrentDay(), ms),
      ids = new Set(revealed.map((photo) => photo.id))
    for (const [id, marker] of markers)
      if (!ids.has(id)) {
        marker.remove()
        markers.delete(id)
      }
    for (const photo of revealed)
      if (!markers.has(photo.id)) {
        const feature = {
          type: "Feature",
          geometry: { type: "Point", coordinates: [photo.lon, photo.lat] },
          properties: photo,
        }
        markers.set(
          photo.id,
          createPhotoMarker({
            map,
            library,
            reader,
            document,
            labels,
            timezone: manager.timezone,
            feature,
          }),
        )
      }
    stack?.sync(revealed)
  }
  return {
    sync,
    get markers() {
      return markers
    },
    destroy() {
      destroyed = true
      stack?.destroy()
      for (const marker of markers.values()) marker.remove()
      markers.clear()
    },
  }
}
