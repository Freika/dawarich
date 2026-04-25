import { RoutesLayer } from "maps_maplibre/layers/routes_layer"
import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"
import { createCircle } from "maps_maplibre/utils/geometry"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"
import { applySpeedColors } from "maps_maplibre/utils/speed_colors"

/**
 * Tracks loading counts across multiple data sources
 * Reports live item counts instead of percentage progress
 */
class LoadingCounter {
  constructor(onUpdate) {
    this.onUpdate = onUpdate
    this.counts = {}
    this.completed = new Set()
    this.expectedSources = new Set()
  }

  /**
   * Register a source that will be tracked.
   * Must be called before fetching begins so the badge shows "0 source" immediately.
   */
  expect(source) {
    this.expectedSources.add(source)
    this._report()
  }

  update(source, count) {
    this.counts[source] = count
    this._report()
  }

  complete(source) {
    this.completed.add(source)
    this._report()
  }

  isComplete() {
    return (
      this.expectedSources.size > 0 &&
      [...this.expectedSources].every((s) => this.completed.has(s))
    )
  }

  _report() {
    if (!this.onUpdate) return
    const fullCounts = {}
    for (const source of this.expectedSources) {
      fullCounts[source] = this.counts[source] || 0
    }
    this.onUpdate({
      counts: fullCounts,
      isComplete: this.isComplete(),
    })
  }
}

/**
 * Handles loading and transforming data from API
 */
export class DataLoader {
  constructor(api, apiKey, settings = {}) {
    this.api = api
    this.apiKey = apiKey
    this.settings = settings
  }

  /**
   * Update settings (called when user changes settings)
   */
  updateSettings(settings) {
    this.settings = settings
  }

  /**
   * Fetch only points data and transform to GeoJSON.
   * Used by ensurePointsLoaded() for lazy-loading point-dependent layers.
   */
  async fetchPointsData(startDate, endDate) {
    const result = await this.api.fetchAllPoints({
      start_at: startDate,
      end_at: endDate,
    })
    const points = result.points
    const pointsGeoJSON = pointsToGeoJSON(points)
    let routesGeoJSON = RoutesLayer.pointsToRoutes(points, {
      distanceThresholdMeters: this.settings.metersBetweenRoutes || 500,
      timeThresholdMinutes: this.settings.minutesBetweenRoutes || 60,
    })

    // Keep original routes before speed coloring for low-zoom rendering
    const routesBaseGeoJSON = routesGeoJSON

    if (this.settings.speedColoredRoutes) {
      const speedColorScale =
        this.settings.speedColorScale ||
        "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300"
      routesGeoJSON = applySpeedColors(routesGeoJSON, points, speedColorScale)
    }

    return { points, pointsGeoJSON, routesGeoJSON, routesBaseGeoJSON }
  }

  /**
   * Fetch all map data (points, visits, photos, areas, tracks)
   * Core data (points, visits, areas, places) loads incrementally.
   * Heavy data (tracks, photos) loads in background via callbacks.
   *
   * @param {string} startDate
   * @param {string} endDate
   * @param {Object} callbacks
   * @param {Function} callbacks.onUpdate - Called with { counts, isComplete }
   * @param {Function} callbacks.onLayerData - Called with (source, geoJSON) when a source has renderable data
   * @param {Function} callbacks.onTracksLoaded - Callback when tracks finish loading
   * @param {Function} callbacks.onPhotosLoaded - Callback when photos finish loading
   */
  async fetchMapData(
    startDate,
    endDate,
    { onUpdate, onLayerData, onTracksLoaded, onPhotosLoaded } = {},
  ) {
    const data = {}

    const counter = onUpdate ? new LoadingCounter(onUpdate) : null

    // Determine whether any layer that depends on points data is enabled
    const needsPoints =
      this.settings.pointsVisible !== false ||
      this.settings.routesVisible !== false ||
      this.settings.heatmapEnabled ||
      this.settings.fogEnabled ||
      this.settings.scratchEnabled

    // Register every source that will be fetched so the badge stays visible
    // until each one finishes. Tracks and photos load in parallel after the
    // core data resolves, but the badge must still wait for them — otherwise
    // the badge disappears while track lines are still painting on the map.
    if (counter) {
      if (needsPoints) counter.expect("points")
      if (this.settings.visitsEnabled) counter.expect("visits")
      if (this.settings.placesEnabled) counter.expect("places")
      if (this.settings.areasEnabled) counter.expect("areas")
      if (this.settings.tracksEnabled) counter.expect("tracks")
      if (this.settings.photosEnabled) counter.expect("photos")
    }

    // Start ALL core fetches in parallel for better progress granularity.
    performanceMonitor.mark("fetch-points")
    const pointsPromise = needsPoints
      ? this.api.fetchAllPoints({
          start_at: startDate,
          end_at: endDate,
          onProgress: counter
            ? ({ loaded }) => counter.update("points", loaded)
            : null,
          onBatch: onLayerData
            ? (accumulatedPoints) => {
                const geoJSON = pointsToGeoJSON(accumulatedPoints)
                onLayerData("points", geoJSON)
                onLayerData("heatmap", geoJSON)
                if (counter) counter.update("points", accumulatedPoints.length)
              }
            : null,
        })
      : Promise.resolve({ points: [], totalPointsInRange: 0 })

    const visitsPromise = this.settings.visitsEnabled
      ? this.api
          .fetchVisits({
            start_at: startDate,
            end_at: endDate,
          })
          .then((result) => {
            if (counter) {
              counter.update("visits", result.length)
              counter.complete("visits")
            }
            if (onLayerData) {
              onLayerData("visits", this.visitsToGeoJSON(result))
            }
            return result
          })
          .catch((error) => {
            console.warn("Failed to fetch visits:", error)
            if (counter) counter.complete("visits")
            return []
          })
      : Promise.resolve([])

    const areasPromise = this.settings.areasEnabled
      ? this.api
          .fetchAreas()
          .then((result) => {
            if (counter) {
              counter.update("areas", result.length)
              counter.complete("areas")
            }
            if (onLayerData) {
              onLayerData("areas", this.areasToGeoJSON(result))
            }
            return result
          })
          .catch((error) => {
            console.warn("Failed to fetch areas:", error)
            if (counter) counter.complete("areas")
            return []
          })
      : Promise.resolve([])

    const placesPromise = this.settings.placesEnabled
      ? this.api
          .fetchPlaces()
          .then((result) => {
            if (counter) {
              counter.update("places", result.length)
              counter.complete("places")
            }
            if (onLayerData) {
              onLayerData("places", this.placesToGeoJSON(result))
            }
            return result
          })
          .catch((error) => {
            console.warn("Failed to fetch places:", error)
            if (counter) counter.complete("places")
            return []
          })
      : Promise.resolve([])

    // Wait for all core data
    const [pointsResult, visits, areas, places] = await Promise.all([
      pointsPromise,
      visitsPromise,
      areasPromise,
      placesPromise,
    ])
    const points = pointsResult.points
    const totalPointsInRange = pointsResult.totalPointsInRange || 0
    performanceMonitor.measure("fetch-points")

    const emptyGeoJSON = { type: "FeatureCollection", features: [] }

    if (needsPoints) {
      // Mark points complete
      if (counter) {
        counter.update("points", points.length)
        counter.complete("points")
      }

      // Transform points to GeoJSON
      performanceMonitor.mark("transform-geojson")
      data.points = points
      data.pointsGeoJSON = pointsToGeoJSON(data.points)
      data.routesGeoJSON = RoutesLayer.pointsToRoutes(data.points, {
        distanceThresholdMeters: this.settings.metersBetweenRoutes || 500,
        timeThresholdMinutes: this.settings.minutesBetweenRoutes || 60,
      })

      // Keep original routes before speed coloring for low-zoom rendering
      data.routesBaseGeoJSON = data.routesGeoJSON

      if (this.settings.speedColoredRoutes) {
        const speedColorScale =
          this.settings.speedColorScale ||
          "0:#00ff00|15:#00ffff|30:#ff00ff|50:#ffff00|100:#ff3300"
        data.routesGeoJSON = applySpeedColors(
          data.routesGeoJSON,
          data.points,
          speedColorScale,
        )
      }
      performanceMonitor.measure("transform-geojson")

      // Update routes layer now that all points are available
      if (onLayerData) {
        onLayerData("routes", data.routesGeoJSON)
        onLayerData("routes-base", data.routesBaseGeoJSON)
        // Final points/heatmap update with complete dataset
        onLayerData("points", data.pointsGeoJSON)
        onLayerData("heatmap", data.pointsGeoJSON)
        // Fog and scratch need all points — update once
        onLayerData("fog", data.pointsGeoJSON)
        onLayerData("scratch", data.pointsGeoJSON)
      }
    } else {
      data.points = []
      data.pointsGeoJSON = emptyGeoJSON
      data.routesGeoJSON = emptyGeoJSON
      data.routesBaseGeoJSON = emptyGeoJSON
    }

    data.totalPointsInRange = totalPointsInRange
    data.visits = visits
    data.visitsGeoJSON = this.visitsToGeoJSON(data.visits)
    data.areas = areas
    data.areasGeoJSON = this.areasToGeoJSON(data.areas)
    data.places = places
    data.placesGeoJSON = this.placesToGeoJSON(data.places)

    // Initialize empty collections for background-loaded data
    data.photos = []
    data.photosGeoJSON = { type: "FeatureCollection", features: [] }
    data.tracksGeoJSON = { type: "FeatureCollection", features: [] }

    // Start background loading of heavy data (tracks, photos). We collect
    // their promises so the caller can await "everything is truly done"
    // (`data.backgroundReady`) before deciding whether to dismiss the
    // loading badge — otherwise the badge can disappear while tracks are
    // still rendering on the map.
    const backgroundPromises = []

    // Background: Fetch tracks
    if (this.settings.tracksEnabled && onTracksLoaded) {
      console.log("[Tracks] Starting background fetch...")
      const tracksTask = this.api
        .fetchTracks({
          start_at: startDate,
          end_at: endDate,
          // Pushes the total tracks count into the badge as soon as page 1's
          // X-Total-Count header arrives, so users see "342 tracks" while the
          // rest of the pages and the on-map render catch up.
          onTotalKnown: counter
            ? (total) => counter.update("tracks", total)
            : null,
        })
        .then((tracksGeoJSON) => {
          const count = tracksGeoJSON.features.length
          console.log(`[Tracks] Background fetch complete: ${count} tracks`)
          data.tracksGeoJSON = tracksGeoJSON
          onTracksLoaded(tracksGeoJSON)
          if (counter) {
            counter.update("tracks", count)
            counter.complete("tracks")
          }
        })
        .catch((error) => {
          console.warn("[Tracks] Background fetch failed:", error.message)
          // Always close the counter — otherwise a transient failure leaves
          // the badge spinning forever.
          if (counter) counter.complete("tracks")
        })
      backgroundPromises.push(tracksTask)
    }

    // Background: Fetch photos
    if (this.settings.photosEnabled && onPhotosLoaded) {
      console.log("[Photos] Starting background fetch...")
      const photosPromise = this.api.fetchPhotos({
        start_at: startDate,
        end_at: endDate,
      })
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Photo fetch timeout")), 15000),
      )

      const photosTask = Promise.race([photosPromise, timeoutPromise])
        .then((photos) => {
          console.log(
            `[Photos] Background fetch complete: ${photos.length} photos`,
          )
          data.photos = photos
          data.photosGeoJSON = this.photosToGeoJSON(photos)
          onPhotosLoaded(data.photosGeoJSON)
          if (counter) {
            counter.update("photos", photos.length)
            counter.complete("photos")
          }
        })
        .catch((error) => {
          console.warn("[Photos] Background fetch failed:", error.message)
          if (counter) counter.complete("photos")
        })
      backgroundPromises.push(photosTask)
    }

    // Always non-rejecting so callers can `await` without try/catch.
    data.backgroundReady = Promise.allSettled(backgroundPromises)

    return data
  }

  /**
   * Convert visits to GeoJSON
   */
  visitsToGeoJSON(visits) {
    return {
      type: "FeatureCollection",
      features: visits.map((visit) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [visit.place.longitude, visit.place.latitude],
        },
        properties: {
          id: visit.id,
          name: visit.name,
          place_name: visit.place?.name,
          status: visit.status,
          started_at: visit.started_at,
          ended_at: visit.ended_at,
          duration: visit.duration,
        },
      })),
    }
  }

  /**
   * Convert photos to GeoJSON
   */
  photosToGeoJSON(photos) {
    return {
      type: "FeatureCollection",
      features: photos
        .filter((photo) => photo.latitude !== 0 && photo.longitude !== 0)
        .map((photo) => {
          // Construct thumbnail URL
          const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.apiKey}&source=${photo.source}`

          return {
            type: "Feature",
            geometry: {
              type: "Point",
              coordinates: [photo.longitude, photo.latitude],
            },
            properties: {
              id: photo.id,
              thumbnail_url: thumbnailUrl,
              taken_at: photo.localDateTime,
              filename: photo.originalFileName,
              city: photo.city,
              state: photo.state,
              country: photo.country,
              type: photo.type,
              source: photo.source,
            },
          }
        }),
    }
  }

  /**
   * Convert places to GeoJSON
   */
  placesToGeoJSON(places) {
    return {
      type: "FeatureCollection",
      features: places.map((place) => ({
        type: "Feature",
        geometry: {
          type: "Point",
          coordinates: [place.longitude, place.latitude],
        },
        properties: {
          id: place.id,
          name: place.name,
          latitude: place.latitude,
          longitude: place.longitude,
          note: place.note,
          // Stringify tags for MapLibre GL JS compatibility
          tags: JSON.stringify(place.tags || []),
          // Use first tag's color if available
          color: place.tags?.[0]?.color || "#6366f1",
        },
      })),
    }
  }

  /**
   * Convert areas to GeoJSON
   * Backend returns circular areas with latitude, longitude, radius
   */
  areasToGeoJSON(areas) {
    return {
      type: "FeatureCollection",
      features: areas.map((area) => {
        // Create circle polygon from center and radius
        // Parse as floats since API returns strings
        const center = [parseFloat(area.longitude), parseFloat(area.latitude)]
        const coordinates = createCircle(center, area.radius)

        return {
          type: "Feature",
          geometry: {
            type: "Polygon",
            coordinates: [coordinates],
          },
          properties: {
            id: area.id,
            name: area.name,
            color: area.color || "#ef4444",
            radius: area.radius,
          },
        }
      }),
    }
  }

  /**
   * Convert tracks to GeoJSON
   */
  tracksToGeoJSON(tracks) {
    return {
      type: "FeatureCollection",
      features: tracks.map((track) => ({
        type: "Feature",
        geometry: {
          type: "LineString",
          coordinates: track.coordinates,
        },
        properties: {
          id: track.id,
          name: track.name,
          color: track.color || "#6366F1",
        },
      })),
    }
  }
}
