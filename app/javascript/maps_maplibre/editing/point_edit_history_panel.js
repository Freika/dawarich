import { translate } from "i18n"
import { formatDistance } from "../utils/format_helpers"

const EARTH_RADIUS_KM = 6371

const ICONS = {
  undo: '<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11"/>',
  redo: '<path d="m15 14 5-5-5-5"/><path d="M20 9H9.5A5.5 5.5 0 0 0 4 14.5A5.5 5.5 0 0 0 9.5 20H13"/>',
  close: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
}

const icon = (name) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`

function distanceKm(from, to) {
  const toRadians = (degrees) => (degrees * Math.PI) / 180
  const dLat = toRadians(to.latitude - from.latitude)
  const dLon = toRadians(to.longitude - from.longitude)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(from.latitude)) *
      Math.cos(toRadians(to.latitude)) *
      Math.sin(dLon / 2) ** 2
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a))
}

// Newest first: steps that can be redone, then the edits in effect. The
// newest edit in effect is the current state of the map.
export function historyItems(history, { distanceUnit = "km" } = {}) {
  const item = (entry, undone, current) => ({
    entry,
    undone,
    current,
    distance: formatDistance(distanceKm(entry.from, entry.to), distanceUnit),
    pointLabel: translate("messages.point_label", { id: entry.pointId }),
  })
  const done = [...history.entries].reverse()
  return [
    ...history.undone.map((entry) => item(entry, true, false)),
    ...done.map((entry, index) => item(entry, false, index === 0)),
  ]
}

// A MapLibre control listing the latest point moves with undo and redo.
export class PointEditHistoryPanel {
  constructor({ onUndo, onRedo, onTravel, onClose, distanceUnit }) {
    this.onUndo = onUndo
    this.onRedo = onRedo
    this.onTravel = onTravel
    this.onClose = onClose
    this.distanceUnit = distanceUnit
    this.container = null
  }

  onAdd() {
    this.container = document.createElement("section")
    this.container.className = "maplibregl-ctrl map-edit-history"
    this.container.dataset.testid = "point-edit-history"
    this.container.setAttribute(
      "aria-label",
      translate("messages.edit_history"),
    )
    this.container.addEventListener("click", (event) => this._onClick(event))
    return this.container
  }

  onRemove() {
    this.container?.remove()
    this.container = null
  }

  render(history) {
    if (!this.container) return
    this.items = historyItems(history, { distanceUnit: this.distanceUnit })

    const header = document.createElement("header")
    header.className = "map-edit-history__header"
    const title = document.createElement("h2")
    title.className = "map-edit-history__title"
    title.textContent = translate("messages.edit_history")
    const capacity = document.createElement("span")
    capacity.className = "map-edit-history__capacity"
    capacity.textContent = `${history.size}/${history.limit}`
    capacity.title = translate("messages.edit_history_capacity", {
      count: history.limit,
    })
    capacity.setAttribute("aria-label", capacity.title)
    const actions = document.createElement("div")
    actions.className = "map-edit-history__actions"
    const divider = document.createElement("span")
    divider.className = "map-edit-history__divider"
    actions.append(
      this._iconButton("undo", translate("messages.undo"), history.canUndo),
      this._iconButton("redo", translate("messages.redo"), history.canRedo),
      divider,
      this._iconButton("close", translate("common.close"), true),
    )
    header.append(title, capacity, actions)

    const list = document.createElement("ol")
    list.className = "map-edit-history__list"
    this.items.forEach((item, index) => {
      list.append(this._row(item, index, history.busy))
    })

    this.container.setAttribute("aria-busy", String(Boolean(history.busy)))
    this.container.replaceChildren(header, list)
  }

  _row(item, index, busy) {
    const row = document.createElement("li")
    row.className = "map-edit-history__entry"
    if (item.undone) row.dataset.state = "undone"
    if (item.current) row.dataset.state = "current"

    const button = document.createElement("button")
    button.type = "button"
    button.className = "map-edit-history__step"
    button.dataset.index = String(index)
    button.disabled = busy
    button.title = translate(
      item.undone ? "messages.redo_to_here" : "messages.undo_to_here",
    )
    if (item.current) button.setAttribute("aria-current", "step")

    const distance = document.createElement("span")
    distance.className = "map-edit-history__distance"
    distance.textContent = item.distance
    const point = document.createElement("span")
    point.className = "map-edit-history__point"
    point.textContent = item.pointLabel
    const time = document.createElement("time")
    time.className = "map-edit-history__time"
    time.dateTime = new Date(item.entry.at).toISOString()
    time.textContent = new Date(item.entry.at).toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    })

    button.append(distance, point, time)
    row.append(button)
    return row
  }

  _iconButton(action, label, enabled) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "map-edit-history__icon"
    button.dataset.action = action
    button.disabled = !enabled
    button.title = label
    button.setAttribute("aria-label", label)
    button.innerHTML = icon(action)
    return button
  }

  _onClick(event) {
    const button = event.target.closest("button")
    if (!button || button.disabled) return
    if (button.dataset.action === "undo") this.onUndo()
    else if (button.dataset.action === "redo") this.onRedo()
    else if (button.dataset.action === "close") this.onClose()
    else if (button.dataset.index != null)
      this.onTravel(this.items[Number(button.dataset.index)].entry)
  }
}
