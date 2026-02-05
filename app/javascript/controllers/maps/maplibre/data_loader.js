import { RoutesLayer } from "maps_maplibre/layers/routes_layer"
import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"
import { createCircle } from "maps_maplibre/utils/geometry"
import { performanceMonitor } from "maps_maplibre/utils/performance_monitor"

/**
 * Tracks loading progress across multiple data sources
 * Dynamically weights only enabled layers for accurate progress tracking
 */
class ProgressTracker {
  constructor(onProgress, settings) {
    this.onProgress = onProgress
    this.settings = settings
    this.sources = {}
    this.weights = this._calculateWeights()
  }

  /**
   * Calculate weights for each data source based on enabled settings
   * Only enabled layers contribute to progress
   */
  _calculateWeights() {
    const weights = {}

    // Points needed for routes/heatmap/fog even if pointsVisible is false
    const needsPoints =
      this.settings.pointsVisible !== false ||
      this.settings.routesVisible !== false ||
      this.settings.heatmapEnabled ||
      this.settings.fogEnabled

    if (needsPoints) weights.points = 1.0

    if (this.settings.visitsEnabled) weights.visits = 0.15
    if (this.settings.placesEnabled) weights.places = 0.1
    if (this.settings.areasEnabled) weights.areas = 0.05
    if (this.settings.tracksEnabled) weights.tracks = 0.2
    if (this.settings.photosEnabled) weights.photos = 0.15

    // Normalize weights so they sum to 1
    const total = Object.values(weights).reduce((a, b) => a + b, 0)
    if (total > 0) {
      for (const key of Object.keys(weights)) {
        weights[key] /= total
      }
    }

    return weights
  }

  /**
   * Update progress for a specific source
   * @param {string} source - Source name (points, visits, places, areas, tracks, photos)
   * @param {number} progress - Progress value 0.0-1.0
   */
  update(source, progress) {
    // Only track sources that have weights (are enabled)
    if (this.weights[source] === undefined) return
    this.sources[source] = Math.min(1.0, Math.max(0.0, progress))
    this._reportProgress()
  }

  /**
   * Mark a source as complete
   * @param {string} source - Source name
   */
  complete(source) {
    // Only track sources that have weights (are enabled)
    if (this.weights[source] === undefined) return
    this.sources[source] = 1.0
    this._reportProgress()
  }

  /**
   * Check if all tracked sources are complete
   * @returns {boolean}
   */
  isComplete() {
    return Object.keys(this.weights).every(
      (source) => this.sources[source] >= 1.0,
    )
  }

  /**
   * Calculate and report combined progress
   */
  _reportProgress() {
    if (!this.onProgress) return

    let combinedProgress = 0
    for (const [source, weight] of Object.entries(this.weights)) {
      const sourceProgress = this.sources[source] || 0
      combinedProgress += sourceProgress * weight
    }

    this.onProgress({
      progress: combinedProgress,
      sources: { ...this.sources },
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
   * Fetch all map data (points, visits, photos, areas, tracks)
   * Core data (points, visits, areas, places) loads synchronously.
   * Heavy data (tracks, photos) loads in background via callbacks.
   *
   * @param {Object} options.onTracksLoaded - Callback when tracks finish loading
   * @param {Object} options.onPhotosLoaded - Callback when photos finish loading
   */
  async fetchMapData(startDate, endDate, onProgress, { onTracksLoaded, onPhotosLoaded } = {}) {
    const data = {}

    // Create progress tracker for all data sources
    const progressTracker = onProgress
      ? new ProgressTracker(onProgress, this.settings)
      : null

    // Fetch points (core data - blocks until complete)
    performanceMonitor.mark("fetch-points")
    data.points = await this.api.fetchAllPoints({
      start_at: startDate,
      end_at: endDate,
      onProgress: progressTracker
        ? ({ progress }) => progressTracker.update("points", progress)
        : null,
    })
    performanceMonitor.measure("fetch-points")

    // Transform points to GeoJSON
    performanceMonitor.mark("transform-geojson")
    data.pointsGeoJSON = pointsToGeoJSON(data.points)
    data.routesGeoJSON = RoutesLayer.pointsToRoutes(data.points, {
      distanceThresholdMeters: this.settings.metersBetweenRoutes || 500,
      timeThresholdMinutes: this.settings.minutesBetweenRoutes || 60,
    })
    performanceMonitor.measure("transform-geojson")

    // Fetch visits, areas, places in parallel with progress tracking
    const [visits, areas, places] = await Promise.all([
      this.api.fetchVisits({
        start_at: startDate,
        end_at: endDate,
        onProgress: progressTracker
          ? ({ progress }) => progressTracker.update("visits", progress)
          : null,
      })
        .then(result => {
          if (progressTracker) progressTracker.complete("visits")
          return result
        })
        .catch(error => {
          console.warn("Failed to fetch visits:", error)
          if (progressTracker) progressTracker.complete("visits")
          return []
        }),
      this.api.fetchAreas()
        .then(result => {
          if (progressTracker) progressTracker.complete("areas")
          return result
        })
        .catch(error => {
          console.warn("Failed to fetch areas:", error)
          if (progressTracker) progressTracker.complete("areas")
          return []
        }),
      this.api.fetchPlaces({
        onProgress: progressTracker
          ? ({ progress }) => progressTracker.update("places", progress)
          : null,
      })
        .then(result => {
          if (progressTracker) progressTracker.complete("places")
          return result
        })
        .catch(error => {
          console.warn("Failed to fetch places:", error)
          if (progressTracker) progressTracker.complete("places")
          return []
        }),
    ])

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
    // These don't block the map from unlocking

    // Background: Fetch tracks
    if (this.settings.tracksEnabled && onTracksLoaded) {
      console.log("[Tracks] Starting background fetch...")
      this.api
        .fetchTracks({ start_at: startDate, end_at: endDate })
        .then((tracksGeoJSON) => {
          console.log(
            `[Tracks] Background fetch complete: ${tracksGeoJSON.features.length} tracks`,
          )
          if (progressTracker) progressTracker.complete("tracks")
          data.tracksGeoJSON = tracksGeoJSON
          onTracksLoaded(tracksGeoJSON)
        })
        .catch((error) => {
          console.warn("[Tracks] Background fetch failed:", error.message)
          if (progressTracker) progressTracker.complete("tracks")
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
          console.log(`[Photos] Background fetch complete: ${photos.length} photos`)
          if (progressTracker) progressTracker.complete("photos")
          data.photos = photos
          data.photosGeoJSON = this.photosToGeoJSON(photos)
          onPhotosLoaded(data.photosGeoJSON)
        })
        .catch((error) => {
          console.warn("[Photos] Background fetch failed:", error.message)
          if (progressTracker) progressTracker.complete("photos")
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
          color: track.color || "#8b5cf6",
        },
      })),
    }
  }
}
