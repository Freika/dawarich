import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "nameInput",
    "latitudeInput",
    "longitudeInput",
    "radiusInput",
    "radiusDisplay",
    "submitButton",
  ]

  connect() {
    this.area = null
    document.addEventListener("area:drawn", (e) => {
      this.open(e.detail.center, e.detail.radius)
    })
  }

  open(center, radius) {
    this.area = { center, radius }
    this.latitudeInputTarget.value = center[1]
    this.longitudeInputTarget.value = center[0]
    this.radiusInputTarget.value = Math.round(radius)
    this.radiusDisplayTarget.textContent = Math.round(radius)
    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this.formTarget.reset()
    this.area = null
    this.radiusDisplayTarget.textContent = "0"
  }

  onSubmitEnd(event) {
    if (event.detail.success) {
      const dataEl = document.getElementById("area-creation-data")
      if (dataEl?.dataset.created === "true") {
        const area = JSON.parse(dataEl.dataset.area)
        document.dispatchEvent(
          new CustomEvent("area:created", { detail: { area } }),
        )
        // Reset data element for next creation
        delete dataEl.dataset.created
        delete dataEl.dataset.area
      }
      this.close()
    }
  }
}
