import { familyLastSeen } from "./time.js"

const escapeHtml = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  )

const colors = [
  "#3b82f6",
  "#10b981",
  "#f59e0b",
  "#ef4444",
  "#8b5cf6",
  "#ec4899",
]
const collection = (features) => ({ type: "FeatureCollection", features })
export function createFamilyOverlay({
  map,
  library,
  locale = "en",
  timers = globalThis,
  now = () => Date.now(),
  colorMode = "index",
  labels,
}) {
  let locations = [],
    history = [],
    popup = null,
    selected = null,
    destroyed = false
  const source = "family-members",
    historySource = "family-history"
  const ids = [
    "family-history-line",
    "family-pulse",
    "family-circles",
    "family-labels",
  ]
  const color = (id, index) =>
    colors[
      (colorMode === "index"
        ? index
        : String(id)
            .split("")
            .reduce((n, c) => n + c.charCodeAt(0), 0)) % colors.length
    ]
  const relative = new Intl.RelativeTimeFormat(locale, { numeric: "auto" })
  const lastSeen = (stamp) => {
    if (labels) return familyLastSeen({ timestamp: stamp }, labels, now())
    const seconds = Math.round((Number(stamp) * 1000 - now()) / 1000)
    if (!Number.isFinite(seconds)) return ""
    const [size, unit] =
      Math.abs(seconds) < 60
        ? [1, "second"]
        : Math.abs(seconds) < 3600
          ? [60, "minute"]
          : Math.abs(seconds) < 86400
            ? [3600, "hour"]
            : [86400, "day"]
    return relative.format(Math.round(seconds / size), unit)
  }
  function data() {
    return collection(
      locations.map((row, index) => ({
        type: "Feature",
        geometry: { type: "Point", coordinates: [row.longitude, row.latitude] },
        properties: {
          id: row.user_id,
          name: row.name || row.email,
          color: color(row.user_id, index),
          lastSeen: lastSeen(row.timestamp),
        },
      })),
    )
  }
  function lines() {
    return collection(
      history
        .filter(
          (m) =>
            m.points?.length >= 2 &&
            locations.some((l) => l.user_id === m.user_id),
        )
        .map((m) => ({
          type: "Feature",
          properties: {
            id: m.user_id,
            color: color(
              m.user_id,
              locations.findIndex((l) => l.user_id === m.user_id),
            ),
          },
          geometry: {
            type: "LineString",
            coordinates: m.points.map((p) => [p[1], p[0]]),
          },
        })),
    )
  }
  function close() {
    popup?.remove()
    popup = null
    selected = null
  }
  function show() {
    const row = locations.find((l) => l.user_id === selected)
    if (!row) {
      close()
      return
    }
    popup ??= new library.Popup({ offset: 16, closeButton: false })
    popup
      .setLngLat([row.longitude, row.latitude])
      .setHTML(
        `<div style="max-width:min(320px,80vw);overflow-wrap:anywhere"><strong>${escapeHtml(row.name || row.email)}</strong><div>${escapeHtml(lastSeen(row.timestamp))}</div></div>`,
      )
      .addTo(map)
  }
  const click = (e) => {
    const id = e.features?.[0]?.properties?.id
    if (locations.some((l) => l.user_id === id)) {
      close()
      selected = id
      show()
    }
  }
  function paint() {
    if (destroyed) return
    map.getSource(source)?.setData(data())
    map.getSource(historySource)?.setData(lines())
    if (popup) show()
  }
  function restore() {
    if (destroyed) return
    if (!map.getSource(source))
      map.addSource(source, { type: "geojson", data: data() })
    if (!map.getSource(historySource))
      map.addSource(historySource, { type: "geojson", data: lines() })
    const configs = [
      {
        id: ids[0],
        type: "line",
        source: historySource,
        paint: {
          "line-color": ["get", "color"],
          "line-width": 3,
          "line-opacity": 0.6,
        },
      },
      {
        id: ids[1],
        type: "circle",
        source,
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["zoom"], 8, 16, 15, 26],
          "circle-color": ["get", "color"],
          "circle-opacity": 0.15,
        },
      },
      {
        id: ids[2],
        type: "circle",
        source,
        paint: {
          "circle-radius": 10,
          "circle-color": ["get", "color"],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
          "circle-opacity": 0.9,
        },
      },
      {
        id: ids[3],
        type: "symbol",
        source,
        layout: {
          "text-field": ["get", "name"],
          "text-font": ["Open Sans Bold", "Arial Unicode MS Bold"],
          "text-size": 12,
          "text-offset": [0, 1.5],
          "text-anchor": "top",
        },
        paint: {
          "text-color": "#111827",
          "text-halo-color": "#ffffff",
          "text-halo-width": 2,
        },
      },
    ]
    for (const layer of configs)
      if (!map.getLayer(layer.id)) map.addLayer(layer)
  }
  restore()
  map.on("style.load", restore)
  map.on("click", "family-circles", click)
  const interval = timers.setInterval(paint, 60000)
  return {
    replace(rows, members = []) {
      if (destroyed) return
      locations = rows.filter(
        (l) =>
          Number.isFinite(l.longitude) &&
          Number.isFinite(l.latitude) &&
          Math.abs(l.longitude) <= 180 &&
          Math.abs(l.latitude) <= 90,
      )
      history = members
      close()
      paint()
    },
    clear() {
      locations = []
      history = []
      close()
      paint()
    },
    destroy() {
      if (destroyed) return
      this.clear()
      destroyed = true
      timers.clearInterval(interval)
      map.off("style.load", restore)
      map.off("click", "family-circles", click)
      for (const id of ids) if (map.getLayer(id)) map.removeLayer(id)
      for (const id of [source, historySource])
        if (map.getSource(id)) map.removeSource(id)
    },
  }
}
