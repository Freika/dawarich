import { createRequestScope } from "./request_scope.js"
export function photosToGeoJSON(photos) {
  return {
    type: "FeatureCollection",
    features: photos
      .filter(
        (photo) =>
          photo.latitude != null &&
          photo.longitude != null &&
          photo.latitude !== 0 &&
          photo.longitude !== 0,
      )
      .map((photo) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [photo.longitude, photo.latitude],
        },
        properties: {
          id: photo.id,
          taken_at: photo.capturedAt || photo.localDateTime,
          filename: photo.originalFileName,
          city: photo.city,
          state: photo.state,
          country: photo.country,
          type: photo.type,
          source: photo.source,
        },
      })),
  }
}
export function createPhotoLoader({
  reader,
  onData,
  onError,
  timers = globalThis,
}) {
  const operations = createRequestScope(timers)
  return {
    async load(range, { signal } = {}) {
      operations.reset()
      const operation = operations.begin(signal)
      try {
        let warned = false
        const photos = await operation.wait(
          reader.pages(
            "photos",
            { start_date: range.startAt, end_date: range.endAt },
            {
              signal: operation.signal,
              onPage: (response) => {
                if (!warned && response.headers?.get("x-photo-source-errors")) {
                  warned = true
                  onError?.("photo_sources_partial", { sources: response.headers.get("x-photo-source-errors").split(",").join(", ") })
                }
              },
            },
          ),
        )
        operation.check()
        onData?.(photosToGeoJSON(photos))
        return "ready"
      } catch (error) {
        if (
          error.name === "AbortError" &&
          (operation.revision !== operations.revision || signal?.aborted)
        )
          return "cancelled"
        if (error.status === 401 && error.code === "photos_unconfigured") {
          onData?.(photosToGeoJSON([]))
          onError?.(error.code)
          return "unconfigured"
        }
        onError?.("photos_load_failed")
        return "failed"
      } finally {
        operation.close()
      }
    },
    destroy: () => operations.destroy(),
  }
}
