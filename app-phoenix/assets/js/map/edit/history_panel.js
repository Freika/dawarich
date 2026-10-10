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

export function formatDistance(distance, unit = "km") {
  const imperial = unit === "mi"
  let value = imperial ? distance * 0.621371 : distance
  if (value < 1) {
    value *= imperial ? 5280 : 1000
    return `${Math.round(value)} ${imperial ? "ft" : "m"}`
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${imperial ? "mi" : "km"}`
}

export function historyItems(history, { distanceUnit = "km", translate }) {
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

export class PointEditHistoryPanel {
  constructor({
    document,
    translate,
    onUndo,
    onRedo,
    onTravel,
    onClose,
    distanceUnit,
  }) {
    this.document = document
    this.translate = translate
    this.onUndo = onUndo
    this.onRedo = onRedo
    this.onTravel = onTravel
    this.onClose = onClose
    this.distanceUnit = distanceUnit
    this.container = null
    this.items = []
  }

  onAdd() {
    this.container = this.document.createElement("section")
    this.container.className = "maplibregl-ctrl map-edit-history"
    this.container.dataset.testid = "point-edit-history"
    this.container.setAttribute(
      "aria-label",
      this.translate("messages.edit_history"),
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
    const t = this.translate
    this.items = historyItems(history, {
      distanceUnit: this.distanceUnit,
      translate: t,
    })
    const header = this._node("header", "map-edit-history__header")
    const title = this._node(
      "h2",
      "map-edit-history__title",
      t("messages.edit_history"),
    )
    const capacity = this._node(
      "span",
      "map-edit-history__capacity",
      `${history.size}/${history.limit}`,
    )
    capacity.title = t("messages.edit_history_capacity", {
      count: history.limit,
    })
    capacity.setAttribute("aria-label", capacity.title)
    const actions = this._node("div", "map-edit-history__actions")
    actions.append(
      this._iconButton("undo", t("messages.undo"), history.canUndo),
      this._iconButton("redo", t("messages.redo"), history.canRedo),
      this._node("span", "map-edit-history__divider"),
      this._iconButton("close", t("common.close"), true),
    )
    header.append(title, capacity, actions)
    const list = this._node("ol", "map-edit-history__list")
    this.items.forEach((item, index) => {
      list.append(this._row(item, index, history.busy))
    })
    this.container.setAttribute("aria-busy", String(Boolean(history.busy)))
    this.container.replaceChildren(header, list)
  }

  _node(tag, className, text) {
    const node = this.document.createElement(tag)
    node.className = className
    if (text != null) node.textContent = text
    return node
  }

  _row(item, index, busy) {
    const row = this._node("li", "map-edit-history__entry")
    if (item.undone) row.dataset.state = "undone"
    if (item.current) row.dataset.state = "current"
    const button = this._node("button", "map-edit-history__step")
    button.type = "button"
    button.dataset.index = String(index)
    button.disabled = busy
    button.title = this.translate(
      item.undone ? "messages.redo_to_here" : "messages.undo_to_here",
    )
    if (item.current) button.setAttribute("aria-current", "step")
    const time = this._node(
      "time",
      "map-edit-history__time",
      new Date(item.entry.at).toLocaleTimeString([], {
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
      }),
    )
    time.dateTime = new Date(item.entry.at).toISOString()
    button.append(
      this._node("span", "map-edit-history__distance", item.distance),
      this._node("span", "map-edit-history__point", item.pointLabel),
      time,
    )
    row.append(button)
    return row
  }

  _iconButton(action, label, enabled) {
    const button = this._node("button", "map-edit-history__icon")
    button.type = "button"
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
