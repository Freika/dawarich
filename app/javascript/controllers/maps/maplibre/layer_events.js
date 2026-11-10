import { shouldShowPointPopup } from "controllers/maps/maplibre/event_handlers"

/**
 * Click, hover and cursor wiring for the map's interactive layers.
 * Mixed into LayerManager; `this` is the LayerManager.
 */
export const layerEvents = {
  /**
   * Setup event handlers for layer interactions
   * Only sets up handlers once to prevent duplicates
   */
  setupLayerEventHandlers(handlers) {
    if (this.eventHandlersSetup) {
      return
    }

    const subscribe = (...args) => {
      const subscription = this.map.on(...args)
      this.eventHandlerCleanups.push(() => {
        if (subscription?.unsubscribe) subscription.unsubscribe()
        else this.map.off(...args)
      })
    }

    // Click handlers
    subscribe("click", "points-mvt", handlers.handlePointClick)
    subscribe("click", "track-points", handlers.handleEditablePointClick)
    subscribe("click", "visits", handlers.handleVisitClick)
    subscribe("click", "photos", handlers.handlePhotoClick)
    subscribe("click", "places", handlers.handlePlaceClick)
    subscribe("click", "places-radius-outline", handlers.handlePlaceClick)

    // Anomalies click handler
    subscribe("click", "anomalies", handlers.handleAnomalyClick)

    // MVT track fragments carry the same id property; the click flow fetches
    // the full geometry by id, so a clipped fragment is a valid entry point.
    subscribe("click", "tracks-mvt", handlers.handleTrackClick)

    const setCursor = (cursor) => {
      this.map.getCanvas().style.cursor = cursor
    }
    for (const layerId of [
      "tracks-mvt",
      "visits",
      "photos",
      "places",
      "places-radius-outline",
      "anomalies",
    ]) {
      subscribe("mouseenter", layerId, () => setCursor("pointer"))
      subscribe("mouseleave", layerId, () => setCursor(""))
    }

    // mousemove, not mouseenter: single points and merged cells sit side by side
    // in this layer, and mouseenter fires only on entering the layer as a whole.
    subscribe("mousemove", "points-mvt", (e) => {
      const properties = e.features?.[0]?.properties
      let cursor = ""
      if (shouldShowPointPopup(properties))
        cursor = handlers.canDragPoint?.(properties) ? "grab" : "pointer"
      else if (properties)
        cursor =
          this.map.getZoom() >= (this.map.getMaxZoom?.() ?? 22)
            ? "pointer"
            : "zoom-in"
      setCursor(cursor)
    })
    subscribe("mouseleave", "points-mvt", () => setCursor(""))
    subscribe("mousemove", "track-points", (e) => {
      const properties = e.features?.[0]?.properties
      setCursor(handlers.canDragPoint?.(properties) ? "grab" : "pointer")
    })
    subscribe("mouseleave", "track-points", () => setCursor(""))
    // Map-level click clears the focused track selection.
    subscribe("click", (e) => {
      // Track points are part of a selected track — clicking them should not clear the selection
      const trackPointFeatures = this.map.getLayer("track-points")
        ? this.map.queryRenderedFeatures(e.point, { layers: ["track-points"] })
        : []
      // Tiled tracks select via their own click handler — without them here a
      // tiled-track click would deselect first and stay deselected whenever
      // the async detail fetch fails.
      const tiledTrackFeatures = this.map.getLayer("tracks-mvt")
        ? this.map.queryRenderedFeatures(e.point, { layers: ["tracks-mvt"] })
        : []
      if (tiledTrackFeatures.length === 0 && trackPointFeatures.length === 0) {
        handlers.clearTrackSelection()
        const tilePointFeatures = this.map.getLayer("points-mvt")
          ? this.map.queryRenderedFeatures(e.point, { layers: ["points-mvt"] })
          : []
        if (tilePointFeatures.length === 0) handlers.clearPointSelection()
      }
    })

    this.eventHandlersSetup = true
  },
}
