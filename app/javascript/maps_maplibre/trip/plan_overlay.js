import { TripPlanLayer } from "maps_maplibre/layers/trip_plan_layer"
import { setButtonActive } from "maps_maplibre/trip/button_state"

export function setPlanVisible(controller, visible) {
  if (!controller.map || !controller.planValue) return

  if (visible) {
    let plan
    try {
      plan = JSON.parse(controller.planValue)
    } catch (_e) {
      return
    }
    controller.planLayer = new TripPlanLayer(controller.map, { numbered: true })
    controller.planLayer.add(plan)
  } else {
    controller.planLayer?.remove()
    controller.planLayer = null
  }

  if (controller.hasPlanToggleBtnTarget) {
    setButtonActive(controller.planToggleBtnTarget, visible)
    controller.planToggleBtnTarget.setAttribute("aria-pressed", String(visible))
  }
}

export function focusPlanStop(controller, { longitude, latitude }) {
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return
  if (!controller.planLayer) setPlanVisible(controller, true)
  controller.planLayer?.focus(longitude, latitude)
}
