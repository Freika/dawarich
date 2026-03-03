import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "nameInput",
    "latitudeInput",
    "longitudeInput",
    "noteInput",
    "nearbyFrame",
    "tagCheckboxes",
    "modalTitle",
    "submitButton",
    "placeIdInput",
  ]

  connect() {
    this.editingPlaceId = null
    this.setupEventListeners()
    this.setupTagListeners()
  }

  setupEventListeners() {
    document.addEventListener("place:create", (e) => {
      this.open(e.detail.latitude, e.detail.longitude)
    })
    document.addEventListener("place:edit", (e) => {
      this.openForEdit(e.detail.place)
    })
  }

  setupTagListeners() {
    if (!this.hasTagCheckboxesTarget) return

    this.tagCheckboxesTarget.addEventListener("change", (e) => {
      if (e.target.type !== "checkbox" || e.target.name !== "place[tag_ids][]")
        return
      const badge = e.target.nextElementSibling
      const color = badge.dataset.color

      if (e.target.checked) {
        badge.classList.remove("badge-outline")
        badge.style.backgroundColor = color
        badge.style.borderColor = color
        badge.style.color = "white"
      } else {
        badge.classList.add("badge-outline")
        badge.style.backgroundColor = "transparent"
        badge.style.borderColor = color
        badge.style.color = color
      }
    })
  }

  open(latitude, longitude) {
    this.editingPlaceId = null
    this.latitudeInputTarget.value = latitude
    this.longitudeInputTarget.value = longitude

    // Set form for creation mode
    this.formTarget.action = "/places"
    this.formTarget.method = "post"
    this.removeMethodOverride()

    if (this.hasModalTitleTarget)
      this.modalTitleTarget.textContent = "Create New Place"
    if (this.hasSubmitButtonTarget)
      this.submitButtonTarget.value = "Create Place"

    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()

    // Load nearby places via Turbo Frame
    this.loadNearbyFrame(latitude, longitude)
  }

  openForEdit(place) {
    this.editingPlaceId = place.id
    this.nameInputTarget.value = place.name
    this.latitudeInputTarget.value = place.latitude
    this.longitudeInputTarget.value = place.longitude

    if (this.hasNoteInputTarget && place.note) {
      this.noteInputTarget.value = place.note
    }

    // Set form for edit mode
    this.formTarget.action = `/places/${place.id}`
    this.addMethodOverride("patch")

    if (this.hasModalTitleTarget)
      this.modalTitleTarget.textContent = "Edit Place"
    if (this.hasSubmitButtonTarget)
      this.submitButtonTarget.value = "Update Place"

    // Check appropriate tag checkboxes
    const tagCheckboxes = this.formTarget.querySelectorAll(
      'input[name="place[tag_ids][]"]',
    )
    tagCheckboxes.forEach((checkbox) => {
      const isSelected = place.tags.some(
        (tag) => tag.id === Number.parseInt(checkbox.value, 10),
      )
      checkbox.checked = isSelected
      checkbox.dispatchEvent(new Event("change", { bubbles: true }))
    })

    this.modalTarget.classList.add("modal-open")
    this.nameInputTarget.focus()

    this.loadNearbyFrame(place.latitude, place.longitude)
  }

  close() {
    this.modalTarget.classList.remove("modal-open")
    this.formTarget.reset()
    this.editingPlaceId = null

    // Reset nearby frame
    if (this.hasNearbyFrameTarget) {
      this.nearbyFrameTarget.innerHTML =
        '<p class="text-sm text-gray-500">Open modal to load nearby suggestions</p>'
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

    const dataEl = document.getElementById("place-creation-data")
    if (!dataEl?.dataset.place) return

    const place = JSON.parse(dataEl.dataset.place)
    const eventName =
      dataEl.dataset.updated === "true" ? "place:updated" : "place:created"

    document.dispatchEvent(new CustomEvent(eventName, { detail: { place } }))

    // Reset data element
    delete dataEl.dataset.place
    delete dataEl.dataset.created
    delete dataEl.dataset.updated

    this.close()
  }

  // --- Private helpers ---

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
