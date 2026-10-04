import { railsBridge } from "rails_bridge"

const controllerFor = async (el) => {
  const root = el.closest("[phx-hook='RailsStimulus']")
  const app = await railsBridge(root).ready
  return app.getControllerForElementAndIdentifier(el, "family-map")
}

export const familyLastSeen = (location, el, now = Date.now()) => {
  const { words, ago, middot } = JSON.parse(el.dataset.familyTimeAgo)
  const minutes = Math.round(Math.abs(now / 1000 - location.timestamp) / 60)
  const buckets = [
    [1, "less_than_x_minutes", 1], [45, "x_minutes", minutes],
    [90, "about_x_hours", 1], [1440, "about_x_hours", Math.round(minutes / 60)],
    [2520, "x_days", 1], [43200, "x_days", Math.round(minutes / 1440)],
    [86400, "about_x_months", Math.round(minutes / 43200)],
    [525600, "x_months", Math.round(minutes / 43200)],
  ]
  let bucket = buckets.find(([limit]) => minutes < limit)
  if (!bucket) {
    const dates = [new Date(location.timestamp * 1000), new Date(now)].sort((a, b) => a - b)
    const from = dates[0].getUTCFullYear() + (dates[0].getUTCMonth() >= 2 ? 1 : 0)
    const to = dates[1].getUTCFullYear() - (dates[1].getUTCMonth() < 2 ? 1 : 0)
    const leaps = (year) => Math.floor(year / 4) - Math.floor(year / 100) + Math.floor(year / 400)
    const offset = minutes - (from > to ? 0 : leaps(to) - leaps(from - 1)) * 1440
    const remainder = offset % 525600
    const years = Math.floor(offset / 525600)
    bucket = [Infinity, remainder < 131400 ? "about_x_years" : remainder < 394200 ? "over_x_years" : "almost_x_years", years + (remainder >= 394200 ? 1 : 0)]
  }
  const [, key, count] = bucket
  const word = typeof words[key] === "string" ? words[key] : words[key][count === 1 ? "one" : "other"]
  return `${middot} ${ago.replace("%{time}", word.replace("%{count}", count))}`
}

export const familyPage = ({
  fetch = globalThis.fetch,
  controller = controllerFor,
  lastSeen = familyLastSeen,
} = {}) => ({
  async mounted() {
    this.fly = (event) => {
      const row = event.target.closest?.("[data-family-member-id]")
      const location = this.locations?.find(
        (item) => String(item.user_id) === row?.dataset.familyMemberId,
      )
      if (location && this.mapController?.map?.loaded()) {
        this.mapController.map.flyTo({
          center: [location.longitude, location.latitude],
          zoom: 15,
          duration: 1000,
        })
      }
    }
    this.el.addEventListener("click", this.fly)
    this.mapController = await controller(this.el)
    if (this.gone) return
    await this.reconnected()
  },
  async reconnected() {
    if (!this.mapController) return
    this.gone = false
    this.abort?.abort()
    const abort = new AbortController()
    this.abort = abort
    try {
      const response = await fetch("/family/locations.json", {
        credentials: "same-origin",
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal: abort.signal,
      })
      if (abort.signal.aborted) return
      if (!response.ok) return this.clear()
      const locations = await response.json()
      if (abort.signal.aborted) return
      this.clear()
      this.locations = locations
      this.mapController.locationsValue = locations
      this.mapController._disconnected = false
      for (const row of this.el.querySelectorAll("[data-family-member-id]")) {
        const location = locations.find(
          (item) => String(item.user_id) === row.dataset.familyMemberId,
        )
        if (!location) continue
        row.classList.add("cursor-pointer")
        const slot = row.querySelector("[data-family-last-seen]")
        if (slot) {
          slot.textContent = lastSeen(location, this.el)
          slot.hidden = false
        }
      }
      this.el.querySelector("[data-family-empty]").hidden = locations.length > 0
      if (locations.length) await this.mapController.initMap()
    } catch (_error) {
      if (!abort.signal.aborted) this.clear()
    }
  },
  clear() {
    this.mapController?.disconnect()
    if (this.mapController) this.mapController.locationsValue = []
    this.locations = []
    for (const row of this.el.querySelectorAll("[data-family-member-id]")) {
      row.classList.remove("cursor-pointer")
      const slot = row.querySelector("[data-family-last-seen]")
      if (slot) {
        slot.textContent = ""
        slot.hidden = true
      }
    }
    this.el.querySelector("[data-family-empty]").hidden = false
  },
  disconnected() {
    this.gone = true
    this.abort?.abort()
    this.clear()
  },
  destroyed() {
    this.disconnected()
    this.el.removeEventListener("click", this.fly)
  },
})

export const FamilyPage = familyPage()
