const DEBOUNCE_MS = 250
const DEFAULT_RADIUS_KM = 1.0
const MOVE_THRESHOLD_M = 100

export class VisitPlaceSearch {
  constructor(visitId, lat, lon, mountEl, apiKey = null) {
    this.visitId = visitId
    this.lat = parseFloat(lat)
    this.lon = parseFloat(lon)
    this.mount = mountEl
    this.apiKey = apiKey
    this.debounceTimer = null
    this.abortController = null
    this.open = false
  }

  authHeaders() {
    return this.apiKey ? { Authorization: `Bearer ${this.apiKey}` } : {}
  }

  toggle() {
    this.open ? this.close() : this.openPanel()
  }

  openPanel() {
    this.open = true
    this.mount.innerHTML = this.shellHtml()
    this.input = this.mount.querySelector("[data-search-input]")
    this.list = this.mount.querySelector("[data-search-results]")
    this.input.addEventListener("input", () => this.onInput())
    this.input.focus()
    this.fetchResults("")
  }

  close() {
    this.open = false
    clearTimeout(this.debounceTimer)
    if (this.abortController) this.abortController.abort()
    this.mount.innerHTML = ""
  }

  onInput() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(
      () => this.fetchResults(this.input.value.trim()),
      DEBOUNCE_MS,
    )
  }

  async fetchResults(query) {
    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()
    this.renderLoading()

    const params = new URLSearchParams({
      lat: this.lat,
      lon: this.lon,
      radius: DEFAULT_RADIUS_KM,
    })
    if (query.length >= 2) params.set("q", query)

    try {
      const res = await fetch(`/api/v1/places/search?${params}`, {
        headers: { Accept: "application/json", ...this.authHeaders() },
        signal: this.abortController.signal,
      })
      const data = await res.json()
      this.render(data.places || [], data.areas || [], query)
    } catch (err) {
      if (err.name === "AbortError") return
      this.renderError()
    }
  }

  render(places, areas, query) {
    const hasExact = places.some(
      (p) => (p.name || "").toLowerCase() === query.toLowerCase(),
    )
    const rows = []

    areas.forEach((a, i) => {
      rows.push(this.areaRow(a, i))
    })
    places.forEach((p, i) => {
      rows.push(this.placeRow(p, i))
    })
    if (query.length >= 2 && !hasExact) rows.push(this.createRow(query))

    this.list.innerHTML = rows.length
      ? rows.join("")
      : `<li class="px-3 py-2 text-xs text-base-content/60">No places found</li>`

    this.bindRows(places, areas, query)
  }

  bindRows(places, areas, query) {
    this.list.querySelectorAll("[data-select-place]").forEach((el) => {
      const place = places[parseInt(el.dataset.selectPlace, 10)]
      el.addEventListener("click", () => this.selectPlace(place))
    })
    this.list.querySelectorAll("[data-select-area]").forEach((el) => {
      const area = areas[parseInt(el.dataset.selectArea, 10)]
      el.addEventListener("click", () => this.selectArea(area))
    })
    const createEl = this.list.querySelector("[data-create-place]")
    if (createEl)
      createEl.addEventListener("click", () => this.createPlace(query))
  }

  async selectPlace(place) {
    const distance = this.distanceMeters(place.latitude, place.longitude)
    try {
      if (distance > MOVE_THRESHOLD_M) {
        const move = window.confirm(
          `This place is ~${Math.round(distance)} m from the visit. Move the visit here?`,
        )
        if (!move) {
          return
        }
      }
      await this.postJson(`/api/v1/visits/${this.visitId}/select_place`, {
        photon: place,
      })
      this.done()
    } catch (_e) {
      this.renderError()
    }
  }

  async selectArea(area) {
    try {
      await this.patchVisit({ area_id: area.id })
      this.done()
    } catch (_e) {
      this.renderError()
    }
  }

  async createPlace(query) {
    try {
      const created = await this.postJson("/api/v1/places", {
        place: {
          name: query,
          latitude: this.lat,
          longitude: this.lon,
          source: "manual",
        },
      })
      await this.patchVisit({ place_id: created.id, name: created.name })
      this.done()
    } catch (_e) {
      this.renderError()
    }
  }

  patchVisit(visitAttrs) {
    return this.sendJson("PATCH", `/api/v1/visits/${this.visitId}`, {
      visit: visitAttrs,
    })
  }

  postJson(url, body) {
    return this.sendJson("POST", url, body)
  }

  async sendJson(method, url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const res = await fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        ...this.authHeaders(),
        ...(token ? { "X-CSRF-Token": token } : {}),
      },
      body: JSON.stringify(body),
    })
    if (!res.ok) throw new Error(`${method} ${url} failed with ${res.status}`)
    return res.json()
  }

  distanceMeters(lat2, lon2) {
    const R = 6371000
    const toRad = (d) => (d * Math.PI) / 180
    const dLat = toRad(lat2 - this.lat)
    const dLon = toRad(lon2 - this.lon)
    const a =
      Math.sin(dLat / 2) ** 2 +
      Math.cos(toRad(this.lat)) *
        Math.cos(toRad(lat2)) *
        Math.sin(dLon / 2) ** 2
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  }

  done() {
    document.dispatchEvent(
      new CustomEvent("visit-place:changed", {
        detail: { visitId: this.visitId },
      }),
    )
    this.close()
  }

  shellHtml() {
    return `
      <div class="visit-search-panel mt-2 border-t border-base-300 pt-2">
        <input type="text" data-search-input placeholder="Search for a place…"
               maxlength="200"
               class="input input-bordered input-xs w-full mb-2"
               onclick="event.stopPropagation()">
        <ul data-search-results class="flex flex-col w-full max-h-48 overflow-y-auto overflow-x-hidden bg-base-100 rounded-box"></ul>
      </div>`
  }

  rowClass() {
    return "block w-full px-2 py-1 rounded cursor-pointer hover:bg-base-200"
  }

  placeRow(place, idx) {
    const meta = [
      this.placeKind(place),
      this.formatDistance(this.distanceMeters(place.latitude, place.longitude)),
    ]
      .filter(Boolean)
      .join(" · ")
    return `<li class="w-full"><a data-select-place="${idx}" onclick="event.stopPropagation()" class="${this.rowClass()}">
      <span class="block truncate">${this.escape(place.name)}</span>
      ${meta ? `<span class="block text-xs opacity-60 truncate">${this.escape(meta)}</span>` : ""}</a></li>`
  }

  areaRow(area, idx) {
    const dist = this.formatDistance(
      this.distanceMeters(area.latitude, area.longitude),
    )
    return `<li class="w-full"><a data-select-area="${idx}" onclick="event.stopPropagation()" class="${this.rowClass()}">
      <span class="block truncate"><span class="badge badge-xs badge-secondary mr-1">Area</span>${this.escape(area.name)}</span>
      ${dist ? `<span class="block text-xs opacity-60 truncate">${this.escape(dist)}</span>` : ""}</a></li>`
  }

  placeKind(place) {
    const raw = place.osm_value || place.osm_key
    if (!raw) return ""
    return raw.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase())
  }

  formatDistance(meters) {
    if (!Number.isFinite(meters)) return ""
    return meters < 1000
      ? `${Math.round(meters)} m`
      : `${(meters / 1000).toFixed(1)} km`
  }

  createRow(query) {
    return `<li class="w-full"><a data-create-place onclick="event.stopPropagation()" class="${this.rowClass()} truncate">
      + Create "<span class="font-medium">${this.escape(query)}</span>" here</a></li>`
  }

  renderLoading() {
    if (this.list)
      this.list.innerHTML = `<li class="px-3 py-2 text-xs text-base-content/60">Searching…</li>`
  }

  renderError() {
    if (this.list)
      this.list.innerHTML = `<li class="px-3 py-2 text-xs text-error">Search unavailable</li>`
  }

  escape(str) {
    const div = document.createElement("div")
    div.textContent = str == null ? "" : String(str)
    return div.innerHTML
  }
}
