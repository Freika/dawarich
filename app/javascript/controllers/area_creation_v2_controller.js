import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"

export default class extends Controller {
  static targets = [
    "modal",
    "modalTitle",
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
    this.editingAreaId = null
    document.addEventListener("area:drawn", (e) => {
      this.open(e.detail.center, e.detail.radius)
    })
    document.addEventListener("area:edit", (e) => {
      this.openForEdit(e.detail.area)
    })
  }

  open(center, radius) {
    this.area = { center, radius }
    this.editingAreaId = null
    this.latitudeInputTarget.value = center[1]
    this.longitudeInputTarget.value = center[0]
    this.radiusInputTarget.value = Math.round(radius)
    this.radiusDisplayTarget.textContent = Math.round(radius)
    this.applyMode("create")
    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()
  }

  // Open the modal in edit mode for an existing area. Mirrors the
  // place_creation_controller pattern: swap the form's action/method,
  // pre-fill inputs, swap title and submit-button label.
  openForEdit(area) {
    this.area = { center: [area.longitude, area.latitude], radius: area.radius }
    this.editingAreaId = area.id
    this.nameInputTarget.value = area.name || ""
    this.latitudeInputTarget.value = area.latitude
    this.longitudeInputTarget.value = area.longitude
    this.radiusInputTarget.value = Math.round(area.radius)
    this.radiusDisplayTarget.textContent = Math.round(area.radius)
    this.applyMode("edit")
    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()
  }

  applyMode(mode) {
    if (mode === "edit" && this.editingAreaId) {
      this.formTarget.action = `/areas/${this.editingAreaId}`
      this.addMethodOverride("patch")
      if (this.hasModalTitleTarget)
        this.modalTitleTarget.textContent = translate("areas.edit")
      if (this.hasSubmitButtonTarget)
        this.submitButtonTarget.value = translate("areas.update")
    } else {
      this.formTarget.action = "/areas"
      this.removeMethodOverride()
      if (this.hasModalTitleTarget)
        this.modalTitleTarget.textContent = translate("areas.create_new")
      if (this.hasSubmitButtonTarget)
        this.submitButtonTarget.value = translate("areas.create")
    }
  }

  // Mirror the radius number input into the display span so users see
  // the value update as they type.
  updateRadiusDisplay() {
    this.radiusDisplayTarget.textContent = this.radiusInputTarget.value || "0"
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this.formTarget.reset()
    this.area = null
    this.editingAreaId = null
    this.radiusDisplayTarget.textContent = "0"
    this.removeMethodOverride()
  }

  onSubmitEnd(event) {
    if (event.detail.success) {
      const eventName =
        this.editingAreaId !== null ? "area:updated" : "area:created"
      document.dispatchEvent(new CustomEvent(eventName))
      this.close()
    }
  }

  addMethodOverride(method) {
    let input = this.formTarget.querySelector('input[name="_method"]')
    if (!input) {
      input = document.createElement("input")
      input.type = "hidden"
      input.name = "_method"
      this.formTarget.prepend(input)
    }
    input.value = method
  }

  removeMethodOverride() {
    const input = this.formTarget.querySelector('input[name="_method"]')
    if (input) input.remove()
  }
}
