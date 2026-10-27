import { pointsToGeoJSON } from "maps_maplibre/utils/geojson_transformers"
import { createCircle } from "maps_maplibre/utils/geometry"
import { LoadingCounter } from "maps_maplibre/utils/loading_counter"
import { visitsToGeoJSON } from "maps_maplibre/utils/visit_features"

export class DataLoader {
  constructor(api, apiKey, settings = {}) {
    this.api = api
    this.apiKey = apiKey
    this.settings = settings
  }

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

    return {
      points,
      pointsGeoJSON,
      allPointsGeoJSON: pointsGeoJSON,
    }
  }

  /**
   * Fetch all non-tile map data (visits, photos, Places, flights)
   * Core data (visits, Places, flights) loads incrementally.
   * Photos load in the background via a callback.
   *
   * @param {string} startDate
   * @param {string} endDate
   * @param {Object} callbacks
   * @param {Function} callbacks.onUpdate - Called with { counts, isComplete }
   * @param {Function} callbacks.onLayerData - Called with (source, geoJSON) when a source has renderable data
   * @param {Function} callbacks.onPhotosLoaded - Callback when photos finish loading
   */
  async fetchMapData(
    startDate,
    endDate,
    { onUpdate, onLayerData, onPhotosLoaded, viewportBounds } = {},
  ) {
    const data = {}

    const counter = onUpdate ? new LoadingCounter(onUpdate) : null
    // Register every source that will be fetched so the badge stays visible
    // until each one finishes. Photos load after the core data resolves, but
    // the badge must still wait for them.
    if (counter) {
      if (this.settings.visitsEnabled) counter.expect("visits")
      if (this.settings.placesEnabled) counter.expect("places")
      if (this.settings.photosEnabled) counter.expect("photos")
      if (this.settings.flightsEnabled) counter.expect("flights")
    }

    // Start ALL core fetches in parallel for better progress granularity.
    const visitsPromise = this.settings.visitsEnabled
      ? this.api
          .fetchVisits({
            start_at: startDate,
            end_at: endDate,
            ...(viewportBounds || {}),
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

    const savedPlacesTagFilters = this.settings.placesTagFilters
    const placesRequest = this.settings.placesEnabled
      ? Array.isArray(savedPlacesTagFilters) &&
        savedPlacesTagFilters.length === 0
        ? Promise.resolve([])
        : this.api.fetchPlaces({
            ...(Array.isArray(savedPlacesTagFilters)
              ? { tag_ids: savedPlacesTagFilters }
              : {}),
            ...(this.settings.showArchivedPlaces
              ? { includeArchived: true }
              : {}),
          })
      : Promise.resolve([])
    const placesPromise = placesRequest
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

    const flightsPromise = this.settings.flightsEnabled
      ? this.api
          .fetchFlights({ start_at: startDate, end_at: endDate })
          .then((result) => {
            const collection = result || {
              type: "FeatureCollection",
              features: [],
            }
            if (counter) {
              counter.update("flights", collection.features?.length || 0)
              counter.complete("flights")
            }
            if (onLayerData) {
              onLayerData("flights", collection)
            }
            return collection
          })
          .catch((error) => {
            console.warn("Failed to fetch flights:", error)
            if (counter) counter.complete("flights")
            return { type: "FeatureCollection", features: [] }
          })
      : Promise.resolve({ type: "FeatureCollection", features: [] })

    // Wait for all core data
    const [visits, places, flights] = await Promise.all([
      visitsPromise,
      placesPromise,
      flightsPromise,
    ])

    const emptyGeoJSON = { type: "FeatureCollection", features: [] }
    // Point and Track history is always tile-backed on the main map. Explicit
    // bounded consumers call fetchPointsData() separately when they need rows.
    data.points = []
    data.pointsGeoJSON = emptyGeoJSON
    data.totalPointsInRange = 0
    data.visits = visits
    data.visitsGeoJSON = this.visitsToGeoJSON(data.visits)
    data.places = places
    data.placesGeoJSON = this.placesToGeoJSON(data.places)
    data.flightsGeoJSON = flights || {
      type: "FeatureCollection",
      features: [],
    }

    // Initialize empty collections for background-loaded data
    data.photos = []
    data.photosGeoJSON = { type: "FeatureCollection", features: [] }

    // Start background photo loading. Collect its promise so the caller can
    // await "everything is truly done" (`data.backgroundReady`) before
    // deciding whether to dismiss the loading badge.
    const backgroundPromises = []

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
    return visitsToGeoJSON(visits)
  }

  /**
   * Convert photos to GeoJSON
   */
  photosToGeoJSON(photos) {
    return {
      type: "FeatureCollection",
      features: photos
        .filter(
          (photo) =>
            photo.latitude != null &&
            photo.longitude != null &&
            photo.latitude !== 0 &&
            photo.longitude !== 0,
        )
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
              taken_at: photo.capturedAt || photo.localDateTime,
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

  placesToGeoJSON(places) {
    return {
      type: "FeatureCollection",
      features: places.flatMap((place) => {
        const center = [parseFloat(place.longitude), parseFloat(place.latitude)]
        const visitRadius = Math.max(parseInt(place.visit_radius, 10) || 50, 1)
        const properties = {
          id: place.id,
          name: place.name,
          latitude: center[1],
          longitude: center[0],
          note: place.note,
          visitRadius,
          nameLocked: Boolean(place.name_locked),
          geofence: place.geofence === true,
          archived: place.archived === true,
          tags: JSON.stringify(place.tags || []),
          color: place.tags?.[0]?.color || "#6366f1",
        }

        return [
          {
            type: "Feature",
            geometry: {
              type: "Polygon",
              coordinates: [createCircle(center, visitRadius)],
            },
            properties: { ...properties, featureKind: "boundary" },
          },
          {
            type: "Feature",
            geometry: { type: "Point", coordinates: center },
            properties: { ...properties, featureKind: "center" },
          },
        ]
      }),
    }
  }
}
