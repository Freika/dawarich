import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { pointsToVisitDraft } from "maps_maplibre/utils/visit_draft"

function mergeThreshold(controller) {
  return (
    controller.settings?.mergeThresholdMinutes ??
    Number(
      controller.element?.querySelector("[data-visit-merge-threshold-minutes]")
        ?.dataset.visitMergeThresholdMinutes ?? 15,
    )
  )
}

export function selectionVisitDraft(controller) {
  return pointsToVisitDraft(
    controller.areaSelectionManager?.selectedPoints || [],
    mergeThreshold(controller),
  )
}

export function warnMultipleStays(draft) {
  if (draft?.multipleStays) Toast.warning(translate("visits.multiple_stays"))
}

export async function prefillVisitFromClick(controller, form, lat, lng) {
  const session = form?.draftForm
  if (!session) return
  const latitudeDelta = (100 / 6371000) * (180 / Math.PI)
  const longitudeDelta = Math.min(
    180,
    latitudeDelta / Math.max(Math.cos((lat * Math.PI) / 180), 0.000001),
  )
  try {
    const { points } = await controller.api.fetchPointsInArea({
      start_at: controller.startDateValue,
      end_at: controller.endDateValue,
      min_latitude: Math.max(-90, lat - latitudeDelta),
      max_latitude: Math.min(90, lat + latitudeDelta),
      min_longitude: Math.max(-180, lng - longitudeDelta),
      max_longitude: Math.min(180, lng + longitudeDelta),
    })
    const draft = pointsToVisitDraft(points, mergeThreshold(controller))
    if (session.applyHistory(draft)) warnMultipleStays(draft)
  } catch (_error) {
    return
  }
}
