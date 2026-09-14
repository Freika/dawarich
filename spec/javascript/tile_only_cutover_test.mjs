import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const read = (path) => readFile(new URL(path, import.meta.url), "utf8")

test("main-map code has no classic Point, Track, or Route renderer switch", async () => {
  const [settings, loader, layers, tracks, panel, controller] =
    await Promise.all([
      read("../../app/javascript/maps_maplibre/utils/settings_manager.js"),
      read("../../app/javascript/controllers/maps/maplibre/data_loader.js"),
      read("../../app/javascript/controllers/maps/maplibre/layer_manager.js"),
      read("../../app/javascript/maps_maplibre/layers/tracks_layer.js"),
      read("../../app/views/map/maplibre/_settings_panel.html.erb"),
      read("../../app/javascript/controllers/maps/maplibre_controller.js"),
    ])

  assert.doesNotMatch(
    settings,
    /tiledPointsActive|bulkPointsRequired|tiledLayerModes/,
  )
  assert.doesNotMatch(loader, /RoutesLayer|fetchTracks\(/)
  assert.doesNotMatch(layers, /PointsLayer|RoutesLayer/)
  assert.doesNotMatch(tracks, /id: this\.id|source: this\.sourceId/)
  assert.doesNotMatch(
    panel,
    /pointsTiledRendering|routesToggle|metersBetweenRoutes/,
  )
  assert.match(
    controller,
    /async handleEntryClick[\s\S]*fetchTrackWithSegments/,
  )
})

test("Trip day-route presentation remains separate", async () => {
  const tripController = await read(
    "../../app/javascript/controllers/trip_maplibre_controller.js",
  )
  const sharedController = await read(
    "../../app/javascript/controllers/shared_trip_map_controller.js",
  )

  assert.match(tripController, /DayRoutesLayer/)
  assert.match(sharedController, /DayRoutesLayer/)
})
