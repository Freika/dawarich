import { RoutesLayer } from "maps_maplibre/layers/routes_layer"
import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"
import { createCircle } from "maps_maplibre/utils/geometry"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"

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
    const points = await this.api.fetchAllPoints({
      start_at: startDate,
      end_at: endDate,
    })
    const pointsGeoJSON = pointsToGeoJSON(points)
    const routesGeoJSON = RoutesLayer.pointsToRoutes(points, {
      distanceThresholdMeters: this.settings.metersBetweenRoutes || 500,
      timeThresholdMinutes: this.settings.minutesBetweenRoutes || 60,
    })
    return { points, pointsGeoJSON, routesGeoJSON }
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

    // Register core sources that will be fetched so the badge shows them immediately.
    // Tracks and photos load in the background after fetchMapData returns,
    // so they are not tracked here — the badge completes with core data.
    if (counter) {
      if (needsPoints) counter.expect("points")
      if (this.settings.visitsEnabled) counter.expect("visits")
      if (this.settings.placesEnabled) counter.expect("places")
      if (this.settings.areasEnabled) counter.expect("areas")
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
      : Promise.resolve([])

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
    const [points, visits, areas, places] = await Promise.all([
      pointsPromise,
      visitsPromise,
      areasPromise,
      placesPromise,
    ])
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
      performanceMonitor.measure("transform-geojson")

      // Update routes layer now that all points are available
      if (onLayerData) {
        onLayerData("routes", data.routesGeoJSON)
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
    }

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

    // Start background loading of heavy data (tracks, photos)

    // Background: Fetch tracks
    if (this.settings.tracksEnabled && onTracksLoaded) {
      console.log("[Tracks] Starting background fetch...")
      this.api
        .fetchTracks({
          start_at: startDate,
          end_at: endDate,
        })
        .then((tracksGeoJSON) => {
          console.log(
            `[Tracks] Background fetch complete: ${tracksGeoJSON.features.length} tracks`,
          )
          data.tracksGeoJSON = tracksGeoJSON
          onTracksLoaded(tracksGeoJSON)
        })
        .catch((error) => {
          console.warn("[Tracks] Background fetch failed:", error.message)
        })
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

      Promise.race([photosPromise, timeoutPromise])
        .then((photos) => {
          console.log(
            `[Photos] Background fetch complete: ${photos.length} photos`,
          )
          data.photos = photos
          data.photosGeoJSON = this.photosToGeoJSON(photos)
          onPhotosLoaded(data.photosGeoJSON)
        })
        .catch((error) => {
          console.warn("[Photos] Background fetch failed:", error.message)
        })
    }

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
      features: photos.map((photo) => {
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
