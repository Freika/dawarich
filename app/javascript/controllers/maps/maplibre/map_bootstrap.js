import { RangeStatistics } from "maps_maplibre/components/range_statistics"
import { PlacePanelBridge } from "maps_maplibre/editing/place_panel_bridge"
import { TimelineSegmentHover } from "maps_maplibre/managers/timeline_segment_hover"
import { ApiClient } from "maps_maplibre/services/api_client"
import { SearchManager } from "maps_maplibre/utils/search_manager"
import { SettingsManager } from "maps_maplibre/utils/settings_manager"
import { AreaSelectionManager } from "./area_selection_manager"
import { consumeCreatePlaceLink } from "./create_place_link"
import { DataLoader } from "./data_loader"
import { EventHandlers } from "./event_handlers"
import { FilterManager } from "./filter_manager"
import { LayerManager } from "./layer_manager"
import { LayerVisibilityManager } from "./layer_visibility_manager"
import { MapDataManager } from "./map_data_manager"
import { PlacesManager } from "./places_manager"
import { VisitsManager } from "./visits_manager"

/**
 * Build the map page's managers once the map exists.
 *
 * The order is a contract: MapDataManager and VisitsManager copy
 * layerManager, dataLoader and filterManager when they are constructed, and
 * the feature managers below read the data managers. Every manager is stored
 * on the controller, where views, the private E2E suite and spec/regressions
 * read it.
 */
export function buildMapFeatures(controller) {
  controller.api = new ApiClient(
    controller.apiKeyValue,
    controller.importIdValue || null,
  )
  const statistics = controller.element.querySelector(
    '[data-testid="map-range-statistics"]',
  )
  if (statistics) {
    // An empty period gets a persistent explanation with a way out, not a
    // toast that disappears while the user is still looking at a blank map.
    const emptyState = controller.element.querySelector(
      '[data-testid="map-empty-state"]',
    )
    controller.rangeStatistics = new RangeStatistics(
      statistics,
      controller.api,
      "km",
      (data) =>
        emptyState?.classList.toggle("hidden", !data || data.points > 0),
    )
  }

  controller.layerManager = new LayerManager(
    controller.map,
    controller.settings,
    controller.api,
    controller,
  )
  controller.dataLoader = new DataLoader(
    controller.api,
    controller.apiKeyValue,
    controller.settings,
  )
  controller.eventHandlers = new EventHandlers(controller.map, controller)
  controller.filterManager = new FilterManager(controller.dataLoader)
  controller.mapDataManager = new MapDataManager(controller)

  controller.areaSelectionManager = new AreaSelectionManager(controller)
  controller.visitsManager = new VisitsManager(controller)
  // The moveend viewport-refetch normally attaches when the user flips the
  // Visits toggle on. When the layer starts enabled by the saved setting,
  // attach it here so panning keeps the dots in sync with the viewport.
  if (controller.settings.visitsEnabled) {
    controller.visitsManager.attachViewportRefetch()
  }
  controller.placesManager = new PlacesManager(controller)
  controller.placePanel = new PlacePanelBridge(controller)
  consumeCreatePlaceLink(controller.placesManager)
  controller.layerVisibilityManager = new LayerVisibilityManager(controller)

  controller.timelineBridge.connect(controller.cleanup)
  controller.timelineSegmentHover = new TimelineSegmentHover(controller, () =>
    SettingsManager.getSetting("tracksEnabled"),
  )

  if (controller.hasSearchInputTarget && controller.hasSearchResultsTarget) {
    controller.searchManager = new SearchManager(
      controller.map,
      controller.apiKeyValue,
    )
    controller.searchManager.initialize(
      controller.searchInputTarget,
      controller.searchResultsTarget,
    )
  } else {
    console.warn(
      "[Maps V2] Search targets not found, search functionality disabled",
    )
  }
}

/** Document events the map reacts to; removed by the controller's cleanup. */
export function listenToDocument(controller) {
  const handlers = {
    // Tab changes load the timeline feed through its Turbo Frame.
    "map-panel:tab-changed": (e) => controller.handleTabChanged(e),
    // A Timeline calendar range change refetches every enabled layer
    // without tearing down the map instance.
    "timeline-feed:date-navigated": (e) =>
      controller.handleTimelineDateNavigated(e),
    "visit:created": (e) => controller.visitsManager.handleVisitCreated(e),
    "visit:updated": (e) => controller.visitsManager.handleVisitUpdated(e),
    "place:created": (e) => controller.placesManager.handlePlaceCreated(e),
    "place:updated": (e) => controller.placesManager.handlePlaceUpdated(e),
  }
  for (const [name, handler] of Object.entries(handlers)) {
    controller.cleanup.addEventListener(document, name, handler)
  }
}
