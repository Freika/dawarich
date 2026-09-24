import { Controller } from "@hotwired/stimulus"

// A plan stop in the itinerary card asks the plan map to fly to it.
export default class extends Controller {
  focus(event) {
    const { longitude, latitude } = event.params
    window.dispatchEvent(
      new CustomEvent("trip-plan:focus", { detail: { longitude, latitude } }),
    )
  }
}
