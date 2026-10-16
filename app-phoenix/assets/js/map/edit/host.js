import { createEditReconciliation } from "./reconcile.js"
import { mapTranslate } from "../ui/translate.js"
import { PointDragGesture } from "./drag.js"
import { MapEditor } from "./editor.js"
import { createPointEditing } from "./runtime.js"

export function createHostEditing({
  map,
  reader,
  pushEvent,
  lifetime,
  getConfig,
  layers,
  document,
  root,
  clearSelection,
  onMoved,
  timers = globalThis,
}) {
  const enabled = () => getConfig().editEnabled === true
  const scope = () => getConfig().range ?? {}
  const identity = (range) =>
    JSON.stringify([
      range.startAt,
      range.endAt,
      range.importId ?? null,
      range.timezone,
    ])
  let sessionScope = identity(scope())
  let styleName = getConfig().styleName
  const reads = (resource, id, options) =>
    reader
      .read(resource, { id, import_id: scope().importId }, options)
      .then((reply) => reply.data)
  const transport = createPointEditing({
    isEditMode: enabled,
    pushEvent,
    setPosition: () => {},
    historyScope: scope,
    timers,
    onUncertain: () => {
      invalidate()
      reader.reset()
      layers.points.refresh()
      layers.tracks.refresh()
    },
  })
  const editor = new MapEditor(map, {
    document,
    clearSelection,
    history: transport.history,
    translate: mapTranslate(getConfig),
    distanceUnit: getConfig().distanceUnit ?? "km",
    readTrack: (id, options) => reads("track", id, options),
    readPoints: (id, options) =>
      reader.pages(
        "track_points",
        { id, import_id: scope().importId },
        options,
      ),
    move: transport.move,
    historyScope: scope,
    editable: enabled(),
    importScoped: Boolean(scope().importId),
    invalidatePoints: () => reader.reset(),
    refreshTiles: () => {
      layers.points.refresh()
      layers.tracks.refresh()
    },
    onError: (message) => {
      const error = root?.querySelector("[data-map-edit-error]")
      if (error) error.textContent = message
    },
    onMoved: (response) => {
      reconciliation.remember(response)
      onMoved?.(response)
      const error = root?.querySelector("[data-map-edit-error]")
      if (error) error.textContent = ""
    },
  })
  const reconciliation = createEditReconciliation({ editor, readTrack: (id) => reads("track", id), reset: () => reader.reset(), invalidate })
  const gesture = new PointDragGesture(map, {
    isEnabled: enabled,
    getEditor: () => editor,
    isSinglePoint: (properties) =>
      Number.isInteger(Number(properties.id)) &&
      Number(properties.count ?? 1) === 1 &&
      Number(properties.point_count ?? 1) === 1,
  })
  gesture.attach()
  lifetime.own(() => {
    gesture.detach()
    transport.destroy()
    editor.dispose()
  })
  function invalidate() {
    gesture.cancel()
    editor.close()
    transport.cancel()
  }
  return {
    invalidate,
    reconcile: reconciliation.reconcile,
    editor,
    transport,
    config(next) {
      const nextScope = identity(next.range ?? {})
      if (nextScope !== sessionScope || next.styleName !== styleName) {
        invalidate()
        transport.history.clear()
        sessionScope = nextScope
        styleName = next.styleName
      }
      editor.edits.panel.distanceUnit = next.distanceUnit ?? "km"
      editor.importScoped = Boolean(next.range?.importId)
      editor.setEditable(next.editEnabled === true)
      editor.reapplyTileFilters()
    },
  }
}
