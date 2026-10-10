import { PointDragGesture } from "./drag.js"
import { MapEditor } from "./editor.js"
import { createPointEditing } from "./runtime.js"

export function createHostEditing({ map, reader, pushEvent, lifetime, getConfig, layers, document }) {
  const enabled = () => getConfig().editEnabled === true
  const scope = () => getConfig().range ?? {}
  const reads = (resource, id, options) => reader.read(resource, { id, import_id: scope().importId }, options).then(reply => reply.data)
  const transport = createPointEditing({ isEditMode: enabled, pushEvent, setPosition: () => {}, historyScope: scope })
  const editor = new MapEditor(map, {
    document,
    readTrack: (id, options) => reads("track", id, options),
    readPoints: (id, options) => reads("track_points", id, options),
    move: transport.move,
    historyScope: scope,
    editable: enabled(),
    importScoped: Boolean(scope().importId),
    invalidatePoints: () => reader.reset(),
    refreshTiles: () => { layers.points.refresh(); layers.tracks.refresh() },
    onError: code => pushEvent("map:failed", { code }),
  })
  const gesture = new PointDragGesture(map, {
    isEnabled: enabled,
    getEditor: () => editor,
    isSinglePoint: properties => Number.isInteger(Number(properties.id)) && Number(properties.point_count ?? 1) === 1,
  })
  gesture.attach()
  lifetime.own(() => { gesture.detach(); transport.destroy(); editor.dispose() })
  return { editor, config(next) { editor.importScoped = Boolean(next.range?.importId); editor.setEditable(next.editEnabled === true); editor.reapplyTileFilters() } }
}
