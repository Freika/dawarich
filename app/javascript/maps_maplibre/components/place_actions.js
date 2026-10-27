import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"

export async function deletePlace(controller, placeId) {
  if (!confirm(translate("places.confirm_delete"))) return

  try {
    const response = await fetch(
      `/api/v1/places/${encodeURIComponent(placeId)}`,
      {
        method: "DELETE",
        headers: {
          Authorization: `Bearer ${controller.apiKeyValue}`,
          "Content-Type": "application/json",
        },
      },
    )
    if (!response.ok) throw new Error("Place deletion failed")
  } catch {
    Toast.error(translate("messages.failed_to_delete_place"))
    return
  }

  removePlaceFeature(controller, placeId)
  controller.closeInfo()
  Toast.success(translate("messages.place_deleted_successfully"))
  await controller.placesManager._refreshPrivacyZones()
}

export function removePlaceFeature(controller, placeId) {
  const layer = controller.layerManager.getLayer("places")
  if (layer?.data) {
    layer.update({
      ...layer.data,
      features: layer.data.features.filter(
        (feature) => String(feature.properties.id) !== String(placeId),
      ),
    })
  }
}
