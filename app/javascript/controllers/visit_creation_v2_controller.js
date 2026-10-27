import { Controller } from "@hotwired/stimulus"
import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { VisitFormDraft } from "maps_maplibre/components/visit_form_draft"

export default class extends Controller {
  static targets = [
    "modal",
    "form",
    "modalTitle",
    "nameInput",
    "startTimeInput",
    "endTimeInput",
    "latitudeInput",
    "longitudeInput",
    "submitButton",
    "placeIdInput",
    "placeName",
    "placeSearch",
  ]

  static values = {
    apiKey: String,
    timezone: { type: String, default: "UTC" },
  }

  connect() {
    this.marker = null
    this.mapController = null
    this.editingVisitId = null
    this._handleVisitEdit = (e) => this.openForEdit(e.detail.visit)
    document.addEventListener("visit:edit", this._handleVisitEdit)
  }

  disconnect() {
    document.removeEventListener("visit:edit", this._handleVisitEdit)
    this.cleanup()
  }

  open(lat, lng, mapController, draft = null) {
    this.draftForm?.close()
    lat = draft?.lat ?? lat
    lng = draft?.lng ?? lng
    this.nameInputTarget.value = draft?.name || ""
    this.editingVisitId = null
    this.mapController = mapController
    this.latitudeInputTarget.value = lat
    this.longitudeInputTarget.value = lng

    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = translate("visits.create_new")
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = translate("visits.create")
    }

    const now = new Date()
    const oneHourLater = new Date(now.getTime() + 60 * 60 * 1000)

    this.startTimeInputTarget.value = this.formatDateTime(
      draft?.startedAt ? new Date(draft.startedAt) : now,
    )
    this.endTimeInputTarget.value = this.formatDateTime(
      draft?.endedAt ? new Date(draft.endedAt) : oneHourLater,
    )

    this.modalTarget.classList.add("modal-open")

    setTimeout(() => this.nameInputTarget.focus(), 100)

    this.addMarker(lat, lng)
    this.draftForm = new VisitFormDraft(this)
    this.draftForm.open(
      draft?.placeId ? { id: draft.placeId, name: draft.name } : null,
    )
  }

  openForEdit(visit) {
    this.draftForm?.close()
    this.editingVisitId = visit.id

    if (this.hasModalTitleTarget) {
      this.modalTitleTarget.textContent = translate("visits.edit")
    }
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.textContent = translate("visits.update")
    }

    const location = [visit.place, visit.area, visit.center, visit].find(
      (candidate) =>
        candidate?.latitude != null && candidate?.longitude != null,
    )
    this.nameInputTarget.value = visit.name || ""
    this.latitudeInputTarget.value = location?.latitude ?? ""
    this.longitudeInputTarget.value = location?.longitude ?? ""

    this.startTimeInputTarget.value = this.formatDateTime(
      new Date(visit.started_at),
    )
    this.endTimeInputTarget.value = this.formatDateTime(
      new Date(visit.ended_at),
    )

    this.modalTarget.classList.add("modal-open")

    setTimeout(() => this.nameInputTarget.focus(), 100)

    const mapElement = document.querySelector(
      '[data-controller*="maps--maplibre"]',
    )
    if (mapElement) {
      const app = window.Stimulus || window.Application
      this.mapController = app?.getControllerForElementAndIdentifier(
        mapElement,
        "maps--maplibre",
      )
    }

    if (location) this.addMarker(location.latitude, location.longitude)
    this.draftForm = new VisitFormDraft(this)
    this.draftForm.open(visit.place)
  }

  togglePlaceSearch() {
    this.draftForm?.search.toggle()
  }

  close() {
    this.draftForm?.close()
    this.modalTarget.classList.remove("modal-open")

    this.formTarget.reset()

    this.editingVisitId = null

    this.removeMarker()
  }

  async submit(event) {
    event.preventDefault()

    const isEdit = this.editingVisitId !== null

    const formData = new FormData(this.formTarget)

    const visitData = {
      visit: {
        name: formData.get("name"),
        started_at: this.localToUTC(formData.get("started_at")),
        ended_at: this.localToUTC(formData.get("ended_at")),
        latitude: parseFloat(formData.get("latitude")),
        longitude: parseFloat(formData.get("longitude")),
        status: "confirmed",
        ...(formData.get("place_id")
          ? { place_id: formData.get("place_id") }
          : {}),
      },
    }

    try {
      const url = isEdit
        ? `/api/v1/visits/${this.editingVisitId}`
        : "/api/v1/visits"
      const method = isEdit ? "PATCH" : "POST"

      const response = await fetch(url, {
        method: method,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.apiKeyValue}`,
          "X-CSRF-Token":
            document.querySelector('meta[name="csrf-token"]')?.content || "",
        },
        body: JSON.stringify(visitData),
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(
          errorData.error || `Failed to ${isEdit ? "update" : "create"} visit`,
        )
      }

      const visit = await response.json()

      this.showToast(
        `Visit ${isEdit ? "updated" : "created"} successfully`,
        "success",
      )

      this.close()

      const eventName = isEdit ? "visit:updated" : "visit:created"
      document.dispatchEvent(
        new CustomEvent(eventName, {
          detail: { visit },
        }),
      )
    } catch (error) {
      console.error(
        `[Visit Creation V2] Error ${isEdit ? "updating" : "creating"} visit:`,
        error,
      )
      this.showToast(
        error.message || `Failed to ${isEdit ? "update" : "create"} visit`,
        "error",
      )
    }
  }

  addMarker(lat, lng) {
    if (!this.mapController) return

    this.removeMarker()

    const el = document.createElement("div")
    el.className = "visit-creation-marker"
    el.innerHTML = "📍"
    el.style.fontSize = "30px"

    const maplibregl = window.maplibregl
    if (maplibregl) {
      this.marker = new maplibregl.Marker({ element: el })
        .setLngLat([lng, lat])
        .addTo(this.mapController.map)
    }
  }

  removeMarker() {
    if (this.marker) {
      this.marker.remove()
      this.marker = null
    }
  }

  cleanup() {
    this.draftForm?.close()
    this.removeMarker()
  }

  formatDateTime(date) {
    const options = {
      timeZone: this.timezoneValue,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }
    const parts = new Intl.DateTimeFormat("en-CA", options).formatToParts(date)
    const get = (type) => parts.find((p) => p.type === type)?.value || "00"
    return `${get("year")}-${get("month")}-${get("day")}T${get("hour")}:${get("minute")}`
  }

  localToUTC(datetimeLocalStr) {
    const asUTC = new Date(`${datetimeLocalStr}Z`)
    const inTZ = this.formatDateTime(asUTC)
    const offsetMs =
      new Date(`${inTZ}Z`).getTime() -
      new Date(`${datetimeLocalStr}Z`).getTime()
    return new Date(
      new Date(`${datetimeLocalStr}Z`).getTime() - offsetMs,
    ).toISOString()
  }

  showToast(message, type = "info") {
    Toast[type](message)
  }
}
