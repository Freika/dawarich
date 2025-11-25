import { pointsToGeoJSON } from 'maps_v2/utils/geojson_transformers'
import { RoutesLayer } from 'maps_v2/layers/routes_layer'
import { createCircle } from 'maps_v2/utils/geometry'
import { performanceMonitor } from 'maps_v2/utils/performance_monitor'

/**
 * Handles loading and transforming data from API
 */
export class DataLoader {
  constructor(api, apiKey) {
    this.api = api
    this.apiKey = apiKey
  }

  /**
   * Fetch all map data (points, visits, photos, areas, tracks)
   */
  async fetchMapData(startDate, endDate, onProgress) {
    const data = {}

    // Fetch points
    performanceMonitor.mark('fetch-points')
    data.points = await this.api.fetchAllPoints({
      start_at: startDate,
      end_at: endDate,
      onProgress: onProgress
    })
    performanceMonitor.measure('fetch-points')

    // Transform points to GeoJSON
    performanceMonitor.mark('transform-geojson')
    data.pointsGeoJSON = pointsToGeoJSON(data.points)
    data.routesGeoJSON = RoutesLayer.pointsToRoutes(data.points)
    performanceMonitor.measure('transform-geojson')

    // Fetch visits
    try {
      data.visits = await this.api.fetchVisits({
        start_at: startDate,
        end_at: endDate
      })
    } catch (error) {
      console.warn('Failed to fetch visits:', error)
      data.visits = []
    }
    data.visitsGeoJSON = this.visitsToGeoJSON(data.visits)

    // Fetch photos
    try {
      console.log('[Photos] Fetching photos from:', startDate, 'to', endDate)
      data.photos = await this.api.fetchPhotos({
        start_at: startDate,
        end_at: endDate
      })
      console.log('[Photos] Fetched photos:', data.photos.length, 'photos')
      console.log('[Photos] Sample photo:', data.photos[0])
    } catch (error) {
      console.error('[Photos] Failed to fetch photos:', error)
      data.photos = []
    }
    data.photosGeoJSON = this.photosToGeoJSON(data.photos)
    console.log('[Photos] Converted to GeoJSON:', data.photosGeoJSON.features.length, 'features')
    console.log('[Photos] Sample feature:', data.photosGeoJSON.features[0])

    // Fetch areas
    try {
      data.areas = await this.api.fetchAreas()
    } catch (error) {
      console.warn('Failed to fetch areas:', error)
      data.areas = []
    }
    data.areasGeoJSON = this.areasToGeoJSON(data.areas)

    // Tracks - DISABLED: Backend API not yet implemented
    // TODO: Re-enable when /api/v1/tracks endpoint is created
    data.tracks = []
    data.tracksGeoJSON = this.tracksToGeoJSON(data.tracks)

    return data
  }

  /**
   * Convert visits to GeoJSON
   */
  visitsToGeoJSON(visits) {
    return {
      type: 'FeatureCollection',
      features: visits.map(visit => ({
        type: 'Feature',
        geometry: {
          type: 'Point',
          coordinates: [visit.place.longitude, visit.place.latitude]
        },
        properties: {
          id: visit.id,
          name: visit.name,
          place_name: visit.place?.name,
          status: visit.status,
          started_at: visit.started_at,
          ended_at: visit.ended_at,
          duration: visit.duration
        }
      }))
    }
  }

  /**
   * Convert photos to GeoJSON
   */
  photosToGeoJSON(photos) {
    return {
      type: 'FeatureCollection',
      features: photos.map(photo => {
        // Construct thumbnail URL
        const thumbnailUrl = `/api/v1/photos/${photo.id}/thumbnail.jpg?api_key=${this.apiKey}&source=${photo.source}`

        return {
          type: 'Feature',
          geometry: {
            type: 'Point',
            coordinates: [photo.longitude, photo.latitude]
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
            source: photo.source
          }
        }
      })
    }
  }

  /**
   * Convert areas to GeoJSON
   * Backend returns circular areas with latitude, longitude, radius
   */
  areasToGeoJSON(areas) {
    return {
      type: 'FeatureCollection',
      features: areas.map(area => {
        // Create circle polygon from center and radius
        const center = [area.longitude, area.latitude]
        const coordinates = createCircle(center, area.radius)

        return {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [coordinates]
          },
          properties: {
            id: area.id,
            name: area.name,
            color: area.color || '#3b82f6',
            radius: area.radius
          }
        }
      })
    }
  }

  /**
   * Convert tracks to GeoJSON
   */
  tracksToGeoJSON(tracks) {
    return {
      type: 'FeatureCollection',
      features: tracks.map(track => ({
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates: track.coordinates
        },
        properties: {
          id: track.id,
          name: track.name,
          color: track.color || '#8b5cf6'
        }
      }))
    }
  }
}
