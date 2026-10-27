import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "nameInput",
    "latitudeInput",
    "longitudeInput",
    "visitRadiusInput",
    "noteInput",
    "nearbyFrame",
    "modalTitle",
    "submitButton",
    "visitIdInput",
  ]

  connect() {
    this.documentListeners = {
      "place:create": (e) =>
        this.open(e.detail.latitude, e.detail.longitude, e.detail),
      "turbo:before-stream-render": (e) => this.relaySavedPlace(e),
    }
    for (const [type, listener] of Object.entries(this.documentListeners)) {
      document.addEventListener(type, listener)
    }
  }

  disconnect() {
    for (const [type, listener] of Object.entries(this.documentListeners)) {
      document.removeEventListener(type, listener)
    }
  }

  // The saved place reaches the page in a turbo stream that Turbo renders
  // after turbo:submit-end, so the map hears about it once that stream lands.
  relaySavedPlace(event) {
    if (event.target?.target !== "place-creation-data") return

    const render = event.detail.render
    event.detail.render = async (stream) => {
      await render(stream)
      this.dispatchSavedPlace()
    }
  }

  dispatchSavedPlace() {
    const dataEl = document.getElementById("place-creation-data")
    if (dataEl?.dataset.deletedId) {
      document.dispatchEvent(
        new CustomEvent("place:deleted", {
          detail: { id: Number(dataEl.dataset.deletedId) },
        }),
      )
      delete dataEl.dataset.deletedId
      return
    }
    const removedId = dataEl?.dataset.removedId
    const duplicateId = dataEl?.dataset.duplicateId
    if (duplicateId || (removedId && dataEl?.dataset.place)) {
      document.dispatchEvent(
        new CustomEvent("place:removed", {
          detail: { id: Number(duplicateId || removedId) },
        }),
      )
    }
    if (!dataEl?.dataset.place && !removedId) return

    const detail = dataEl.dataset.place
      ? { place: JSON.parse(dataEl.dataset.place) }
      : { removedId: Number(removedId) }
    const eventName =
      dataEl.dataset.updated === "true" ? "place:updated" : "place:created"

    document.dispatchEvent(new CustomEvent(eventName, { detail }))
    if (dataEl.dataset.visitId) {
      document.dispatchEvent(
        new CustomEvent("visit-place:changed", {
          detail: { visitId: Number.parseInt(dataEl.dataset.visitId, 10) },
        }),
      )
    }

    delete dataEl.dataset.place
    delete dataEl.dataset.created
    delete dataEl.dataset.updated
    delete dataEl.dataset.visitId
    delete dataEl.dataset.removedId
    delete dataEl.dataset.duplicateId
  }

  open(latitude, longitude, options = {}) {
    this.latitudeInputTarget.value = latitude
    this.longitudeInputTarget.value = longitude
    this.visitIdInputTarget.value = options.visitId || ""
    this.nameInputTarget.value = options.name || ""
    this.visitRadiusInputTarget.value = 50

    // Set form for creation mode
    this.formTarget.action = "/places"
    this.formTarget.method = "post"

    if (this.hasModalTitleTarget)
      this.modalTitleTarget.textContent = translate("places.create_new")
    if (this.hasSubmitButtonTarget)
      this.submitButtonTarget.value = translate("places.create")

    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()

    // Load nearby places via Turbo Frame
    this.loadNearbyFrame(latitude, longitude)
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this.formTarget.reset()

    // Reset nearby frame
    if (this.hasNearbyFrameTarget) {
      this.nearbyFrameTarget.innerHTML = `<p class="text-sm text-gray-500">${translate("places.open_for_suggestions")}</p>`
    }

    document.dispatchEvent(new CustomEvent("place:create:cancelled"))
  }

  loadNearbyFrame(latitude, longitude) {
    if (!this.hasNearbyFrameTarget) return

    this.nearbyFrameTarget.src = `/places/nearby?latitude=${latitude}&longitude=${longitude}&radius=0.5&limit=5`
  }

  selectNearby(event) {
    const el = event.currentTarget
    this.nameInputTarget.value = el.dataset.placeName
    this.latitudeInputTarget.value = el.dataset.placeLatitude
    this.longitudeInputTarget.value = el.dataset.placeLongitude
  }

  onSubmitEnd(event) {
    if (!event.detail.success) return

    this.close()
  }
}
