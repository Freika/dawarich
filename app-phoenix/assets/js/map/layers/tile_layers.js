import { TileExclusions } from "./tile_exclusions.js"
import { PointsMvtLayer } from "./points_mvt.js"
import { TracksMvtLayer } from "./tracks_mvt.js"
import { createTileFreshness } from "../data/tile_freshness.js"

export function createBaseLayers({
  map,
  config,
  freshness = createTileFreshness(),
  onError,
  onEmptyTracks,
}) {
  let current = config
  let destroyed = false
  let editing = null
  const exclusions = new TileExclusions(map)
  const points = new PointsMvtLayer(map, {
    freshness,
    styleName: config.styleName,
    onTileError: () => onError?.("point_tiles_failed"),
  })
  const tracks = new TracksMvtLayer(map, {
    freshness,
    onTileError: () => onError?.("track_tiles_failed"),
    onEmptyTracks,
  })
  function mount() {
    if (destroyed) return
    for (const layer of [points, tracks]) {
      layer.startAt = current.range?.startAt ?? null
      layer.endAt = current.range?.endAt ?? null
      layer.importId = current.range?.importId ?? null
      layer.add()
    }
    points.toggle(current.pointsEnabled !== false)
    points.setHeatmapVisible(current.heatmapEnabled === true)
    points.setFlightWindows(current.flightWindows ?? [])
    tracks.setEnabled(current.tracksEnabled === true)
    tracks.setFlightWindows(current.flightWindows ?? [])
    tracks.setColors({ trackColor: current.trackColor })
    if (editing) exclusions.apply(editing)
  }
  map.on("style.load", mount)
  return {
    points,
    tracks,
    edit(selection) {
      if (destroyed) return
      editing = selection
      if (selection) exclusions.apply(selection)
      else exclusions.restore()
    },
    mount,
    update(next) {
      if (destroyed) return
      const changed = current.epoch !== next.epoch
      current = next
      for (const layer of [points, tracks]) {
        layer.importId = current.range?.importId ?? null
        layer.update({
          startAt: current.range?.startAt,
          endAt: current.range?.endAt,
        })
        if (changed) layer.refresh()
      }
      mount()
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      map.off("style.load", mount)
      points.remove()
      tracks.remove()
      freshness.destroy()
    },
  }
}
