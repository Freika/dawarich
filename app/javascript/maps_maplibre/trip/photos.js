import { PhotosLayer } from "maps_maplibre/layers/photos_layer"
import { ApiClient } from "maps_maplibre/services/api_client"
import { setButtonActive } from "maps_maplibre/trip/button_state"
import { featureToPhoto } from "maps_maplibre/utils/feature_to_photo"

export async function toggleTripPhotos(controller) {
  controller.photosActive = !controller.photosActive

  if (!controller.photosActive) {
    if (controller.photosLayer) {
      controller.photosLayer.remove()
      controller.photosLayer = null
    }
    setButtonActive(controller.photosToggleBtnTarget, false)
    if (controller.replayPanel?.isOpen)
      controller.replayPanel.refreshReplayPhotos()
    return
  }

  if (!controller.photosGeoJSON) {
    const apiClient = new ApiClient(controller.apiKeyValue)
    try {
      const photos = await apiClient.fetchPhotos({
        start_at: controller.startedAtValue,
        end_at: controller.endedAtValue,
      })
      controller.photosGeoJSON = photosToGeoJSON(photos, controller.apiKeyValue)
    } catch (e) {
      console.error("[TripMapLibre] Error fetching photos:", e)
      controller.photosActive = false
      return
    }
  }

  if (controller.photosGeoJSON.features.length === 0) {
    controller.photosActive = false
    return
  }

  controller.photosLayer = new PhotosLayer(controller.map)
  controller.photosLayer.add(controller.photosGeoJSON)
  setButtonActive(controller.photosToggleBtnTarget, true)
  if (controller.replayPanel?.isOpen)
    controller.replayPanel.refreshReplayPhotos()
}

export function tripReplayPhotos(controller) {
  return controller.photosActive && controller.photosGeoJSON
    ? controller.photosGeoJSON.features.map(featureToPhoto)
    : []
}

export function setTripReplayPhotosActive(controller, active) {
  if (!controller.photosLayer) return
  if (active) {
    controller._photosWasVisible = controller.photosLayer.visible
    controller.photosLayer.hide()
  } else if (controller._photosWasVisible) {
    controller.photosLayer.show()
  }
}

function photosToGeoJSON(photos, apiKey) {
  return {
    type: "FeatureCollection",
    features: photos.map((photo) => {
      const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${apiKey}&source=${photo.source}`
      return {
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [photo.longitude, photo.latitude],
        },
        properties: {
          id: photo.id,
          thumbnail_url: thumbnailUrl,
          taken_at: photo.capturedAt || photo.localDateTime,
          filename: photo.originalFileName,
          city: photo.city,
          state: photo.state,
          country: photo.country,
          type: photo.type,
          source: photo.source,
        },
      }
    }),
  }
}
