import {
  areasToGeoJSON,
  placesToGeoJSON,
  visitsToGeoJSON,
} from "../data/entity_geojson.js"
import { createRequestScope } from "../data/request_scope.js"
import { AnomaliesLayer } from "./anomalies.js"
import { AreasLayer } from "./areas.js"
import { PlacesLayer } from "./places.js"
import { SelectedPointsLayer } from "./selected_points.js"
import { VisitsLayer } from "./visits.js"

const empty = () => ({ type: "FeatureCollection", features: [] })
export function createEntityLayers({
  map,
  reader,
  library,
  onSelect,
  onError,
  timers = globalThis,
}) {
  const operations = createRequestScope(timers)
  let pendingUpdates = 0
  let queuedViewport = false
  const resources = { visits: null, places: null, areas: null, anomalies: null }
  const clicks = {}
  let current = {},
    presentation = {},
    selection,
    popup,
    destroyed = false
  const definitions = {
    visits: {
      Class: VisitsLayer,
      flag: "visitsEnabled",
      kind: "visit",
      convert: visitsToGeoJSON,
    },
    places: {
      Class: PlacesLayer,
      flag: "placesEnabled",
      kind: "place",
      convert: placesToGeoJSON,
    },
    areas: {
      Class: AreasLayer,
      flag: "areasEnabled",
      kind: "area",
      convert: areasToGeoJSON,
    },
    anomalies: {
      Class: AnomaliesLayer,
      flag: "anomaliesEnabled",
      kind: "point",
    },
  }
  function visitPresentation(next = presentation) {
    presentation = next
    const visits = resources.visits
    if (!visits) return
    visits.setSelectedVisit(presentation.selectedId)
    visits.setStatusFilter(presentation.status)
    visits.setDayRoute(presentation.dayRoute)
  }
  function closePopup() {
    popup?.remove()
    popup = null
  }
  function restore() {
    if (destroyed) return
    closePopup()
    for (const layer of Object.values(resources))
      if (layer && !map.getSource(layer.sourceId)) layer.add(layer.data)
    if (selection && !map.getSource(selection.sourceId))
      selection.add(selection.data)
    visitPresentation()
  }
  function attach(kind, layer) {
    const identity = definitions[kind].kind
    const id = kind === "areas" ? "areas-fill" : layer.id
    const click = (event) => {
      if (destroyed || !layer.visible) return
      const candidate = event.features?.[0]?.properties?.id
      const feature = layer.data?.features.find(
        (feature) => feature.properties.id === candidate,
      )
      if (!feature) return
      closePopup()
      if (kind === "anomalies")
        popup = new library.Popup({ closeButton: true, closeOnClick: true })
          .setLngLat(event.lngLat ?? feature.geometry.coordinates)
          .setHTML(layer.buildPopupContent(feature.properties))
          .addTo(map)
      onSelect?.({ kind: identity, id: feature.properties.id })
    }
    clicks[kind] = { id, click }
    map.on("click", id, click)
  }
  function remove(kind) {
    const layer = resources[kind]
    if (!layer) return
    map.off("click", clicks[kind].id, clicks[kind].click)
    delete clicks[kind]
    layer.remove()
    resources[kind] = null
  }
  async function update(config, { signal, viewportOnly = false } = {}) {
    operations.reset()
    const operation = operations.begin(signal)
    current = config
    pendingUpdates++
    closePopup()
    try {
      const pending = []
      for (const [kind, definition] of Object.entries(definitions)) {
        if (viewportOnly && kind !== "visits") continue
        if (!config[definition.flag]) {
          remove(kind)
          continue
        }
        if (!resources[kind]) {
          const layer = new definition.Class(map, {
            reader,
            timers,
            onError,
            visible: true,
            labels: config.entityLabels,
            timezone: config.range.timezone,
          })
          resources[kind] = layer
          layer.add(empty())
          attach(kind, layer)
        }
        const layer = resources[kind]
        if (kind === "anomalies") {
          layer.labels = config.entityLabels ?? {}
          layer.timezone = config.range.timezone ?? "UTC"
        }
        const load = async () => {
          let data
          if (kind === "anomalies")
            data = await operation.wait(
              layer.fetchAnomalies(
                {
                  start_at: config.range.startAt,
                  end_at: config.range.endAt,
                  import_id: config.range.importId,
                },
                { signal: operation.signal },
              ),
            )
          else {
            const tags = config.placesTagFilters
            const params =
              kind === "visits"
                ? {
                    start_at: config.range.startAt,
                    end_at: config.range.endAt,
                    ...viewport(map),
                  }
                : kind === "places" && Array.isArray(tags)
                  ? { tag_ids: tags }
                  : {}
            const rows =
              kind === "places" && Array.isArray(tags) && !tags.length
                ? []
                : await operation.wait(
                    reader.pages(kind, params, { signal: operation.signal }),
                  )
            operation.check()
            data = definition.convert(rows)
          }
          operation.check()
          return [layer, data]
        }
        pending.push(load())
      }
      const loaded = await operation.wait(Promise.all(pending))
      operation.check()
      for (const [layer, data] of loaded) layer.update(data)
      visitPresentation()
    } catch (error) {
      if (operation.revision === operations.revision && !signal?.aborted)
        onError?.("entity_load_failed")
      throw error
    } finally {
      operation.close()
      pendingUpdates--
      if (!pendingUpdates && queuedViewport) {
        queuedViewport = false
        moved()
      }
    }
  }
  const moved = () => {
    if (destroyed || !current.visitsEnabled) return
    if (pendingUpdates) {
      queuedViewport = true
      return
    }
    update(current, { viewportOnly: true }).catch(() => {})
  }
  map.on("style.load", restore)
  map.on("moveend", moved)
  return {
    update,
    visitPresentation,
    selected(data) {
      if (destroyed) return
      if (!selection) {
        selection = new SelectedPointsLayer(map)
        selection.add(empty())
      }
      selection.updateSelectedPoints(data)
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      operations.destroy()
      closePopup()
      map.off("style.load", restore)
      map.off("moveend", moved)
      for (const kind of Object.keys(resources)) remove(kind)
      selection?.clearSelection()
      selection?.remove()
      selection = null
      presentation = {}
      current = {}
    },
  }
}
function viewport(map) {
  const bounds = map.getBounds?.()
  if (!bounds) return {}
  const values = {
    sw_lat: bounds.getSouth(),
    sw_lng: bounds.getWest(),
    ne_lat: bounds.getNorth(),
    ne_lng: bounds.getEast(),
  }
  return Object.values(values).every(Number.isFinite)
    ? { selection: "true", ...values }
    : {}
}
