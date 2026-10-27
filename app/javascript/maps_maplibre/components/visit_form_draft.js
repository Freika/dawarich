import { translate } from "i18n"
import { VisitPlaceSearch } from "maps_maplibre/components/visit_place_search"

export class VisitFormDraft {
  constructor(controller) {
    this.controller = controller
    this.active = true
    this.revision = 0
    this.editedTimes = new Set()
    this.nameEdited = Boolean(
      controller.editingVisitId != null &&
        controller.nameInputTarget.value.trim(),
    )
    this.events = new AbortController()
    controller.nameInputTarget.addEventListener(
      "input",
      () => {
        this.nameEdited = true
      },
      { signal: this.events.signal },
    )
    for (const target of ["startTimeInputTarget", "endTimeInputTarget"]) {
      controller[target].addEventListener(
        "input",
        () => this.editedTimes.add(target),
        { signal: this.events.signal },
      )
    }
  }

  async open(place = null) {
    const c = this.controller
    this.placeChosen = false
    c.placeIdInputTarget.value = ""
    c.placeNameTarget.textContent = translate("visits.choose_place")
    this.search = new VisitPlaceSearch(
      null,
      c.latitudeInputTarget.value,
      c.longitudeInputTarget.value,
      c.placeSearchTarget,
      c.apiKeyValue,
      { onSelect: (selected) => this.select(selected) },
    )
    if (place?.id) {
      this.select(place)
      return
    }
    await this.loadContext()
  }

  select(place, fillName = true) {
    this.placeChosen = true
    const c = this.controller
    c.placeIdInputTarget.value = place.id
    c.placeNameTarget.textContent = place.name
    if (fillName) this.fillName(place.name)
  }

  fillName(name) {
    if (!this.nameEdited) {
      this.controller.nameInputTarget.value = name || ""
    }
  }

  async loadContext() {
    const revision = ++this.revision
    const c = this.controller
    const params = new URLSearchParams({
      lat: c.latitudeInputTarget.value,
      lon: c.longitudeInputTarget.value,
      radius: 0.1,
      limit: 50,
      mask_privacy_zones: true,
    })
    try {
      const response = await fetch(`/api/v1/places/search?${params}`, {
        headers: { Authorization: `Bearer ${c.apiKeyValue}` },
        signal: this.events.signal,
      })
      if (!response.ok) return
      const { places = [] } = await response.json()
      if (!this.active || revision !== this.revision || this.placeChosen) return
      const nearest = places
        .filter(
          (place) =>
            place.id &&
            place.has_visits &&
            this.search.distanceMeters(place.latitude, place.longitude) <= 100,
        )
        .sort(
          (a, b) =>
            this.search.distanceMeters(a.latitude, a.longitude) -
            this.search.distanceMeters(b.latitude, b.longitude),
        )[0]
      if (nearest) {
        this.select(nearest, false)
        this.placeChosen = false
        this.fillName(nearest.name)
      } else {
        c.placeIdInputTarget.value = ""
        c.placeNameTarget.textContent = translate("visits.choose_place")
        this.fillName(places.find((place) => !place.id)?.name)
      }
    } catch (_error) {
      return
    }
  }

  applyHistory(draft) {
    if (!this.active || !draft) return false
    const c = this.controller
    for (const [target, value] of [
      ["startTimeInputTarget", draft.startedAt],
      ["endTimeInputTarget", draft.endedAt],
    ]) {
      if (!this.editedTimes.has(target)) {
        c[target].value = c.formatDateTime(new Date(value))
      }
    }
    c.latitudeInputTarget.value = draft.lat
    c.longitudeInputTarget.value = draft.lng
    c.addMarker(draft.lat, draft.lng)
    this.search.lat = draft.lat
    this.search.lon = draft.lng
    if (!this.placeChosen) this.loadContext()
    return true
  }

  close() {
    this.active = false
    this.events.abort()
    this.search?.close()
  }
}
