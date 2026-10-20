import { formatTimestamp } from "../algorithms/geojson.js"
import { mapTranslate } from "./translate.js"

const escape = (value) =>
  value == null
    ? ""
    : String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")

const line = (label, value) =>
  `<div><span class="font-semibold">${label}:</span> ${value}</div>`

function storedCoordinates({ latitude, longitude }) {
  if (latitude == null || longitude == null) return null
  if (latitude === "" || longitude === "") return null
  const lat = Number(latitude)
  const lon = Number(longitude)
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null
  return `${lat.toFixed(6)}, ${lon.toFixed(6)}`
}

function formatSpeed(kmh, unit) {
  return unit === "km"
    ? `${Math.round(kmh)} km/h`
    : `${Math.round(kmh * 0.621371)} mph`
}

export function createInfoCard({
  root,
  pushEvent,
  getConfig,
  lifetime,
  confirm = (message) => globalThis.confirm(message),
}) {
  const find = (name) => root?.querySelector(`[data-native-info-${name}]`)
  const translate = mapTranslate(getConfig)
  let entity = null

  function show(heading, html, buttons = []) {
    const card = find("display")
    if (!card) return
    entity = null
    find("title").textContent = heading
    find("content").innerHTML = html
    find("actions").innerHTML = buttons
      .map(
        ({ action, id, type, label }) =>
          `<button class="btn btn-sm ${action === "delete" ? "btn-error" : "btn-primary"}" data-native-info-action="${action}" data-id="${id}" data-entity-type="${type}">${label}</button>`,
      )
      .join("")
    card.classList.remove("hidden")
    pushEvent("map:panel", { panel: "tools" })
  }

  function close() {
    find("display")?.classList.add("hidden")
  }

  function point(properties, geometry) {
    const unit = getConfig().distanceUnit || "km"
    const coords = geometry?.coordinates
    const coordinates =
      storedCoordinates(properties) ??
      (coords?.length >= 2
        ? `${coords[1].toFixed(6)}, ${coords[0].toFixed(6)}`
        : null)
    const id = properties.id
    const timezone = getConfig().range?.timezone
    show(
      translate("map_info.location_point"),
      `<div class="space-y-2">${id ? `<turbo-frame id="point-address-${id}"></turbo-frame>` : ""}${
        coordinates ? line(translate("map_info.coordinates"), coordinates) : ""
      }${line(translate("map_info.time"), formatTimestamp(properties.timestamp, timezone))}${
        properties.battery
          ? line(translate("map_info.battery"), `${properties.battery}%`)
          : ""
      }${
        properties.altitude
          ? line(translate("map_info.altitude"), `${Math.round(properties.altitude)}m`)
          : ""
      }${
        properties.velocity
          ? line(translate("map_info.speed"), formatSpeed(properties.velocity * 3.6, unit))
          : ""
      }</div>`,
      id ? [{ action: "delete", id, type: "point", label: translate("messages.delete") }] : [],
    )
    if (!id) return
    entity = { type: "point", id }
    pushEvent("address:open", { id }, (reply) => {
      const frame = find("content")?.querySelector(`#point-address-${id}`)
      if (frame && reply?.text && entity?.id === id)
        frame.innerHTML = `<div><span class="font-semibold">${translate("points.address.address")}</span> ${escape(reply.text)}</div>`
    })
  }

  function place(properties) {
    const lock = properties.nameLocked
      ? `<div class="text-xs opacity-70" data-testid="place-name-lock">${translate("map_info.place_name_locked")}</div>`
      : ""
    show(
      escape(properties.name) || translate("map_info.place"),
      `<div class="space-y-2">${lock}</div>`,
      properties.id
        ? [{ action: "edit", id: properties.id, type: "place", label: translate("messages.edit") }]
        : [],
    )
  }

  function area(properties) {
    const { radius, latitude, longitude, id } = properties
    show(
      escape(properties.name) || translate("map_info.area"),
      `<div class="space-y-2">${radius ? line(translate("map_info.radius"), `${Math.round(radius)}m`) : ""}${
        latitude && longitude
          ? line(translate("map_info.center"), `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`)
          : ""
      }</div>`,
      id
        ? [
            { action: "edit", id, type: "area", label: translate("messages.edit") },
            { action: "delete", id, type: "area", label: translate("messages.delete") },
          ]
        : [],
    )
    entity = { type: "area", id, name: properties.name }
  }

  function act({ action, id, entityType }) {
    if (action === "edit") {
      pushEvent(entityType === "area" ? "area:edit" : "place:edit", { id })
    } else if (entityType === "area") {
      const name = entity?.type === "area" ? entity.name : ""
      if (confirm(translate("areas.confirm_delete_named", { name }))) {
        pushEvent("area:delete", { id })
        close()
      }
    } else if (entityType === "point") {
      if (confirm(translate("map.confirm_delete_point_permanently"))) {
        pushEvent("point:delete", { point_id: id })
        close()
      }
    }
  }

  function select({ kind, properties, content }) {
    if (kind === "place") place(properties)
    else if (kind === "area") area(properties)
    else if (content !== undefined) show(translate("messages.anomaly_point"), content)
    else return false
    return true
  }

  const click = (event) => {
    if (!event.target?.closest?.("[data-native-info-display]")) return
    const button = event.target.closest("[data-native-info-action]")
    if (button) return act(button.dataset)
    if (event.target?.closest?.("[data-native-info-close]")) close()
  }
  root?.addEventListener("click", click)
  lifetime?.own(() => root?.removeEventListener("click", click))

  return { show, close, point, place, area, select }
}
