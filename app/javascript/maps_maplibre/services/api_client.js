import { translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"
import { maskPrivacyZones } from "./api/helpers"
import { pointsApi } from "./api/points_api"
import { tracksApi } from "./api/tracks_api"
import { visitsPlacesApi } from "./api/visits_places_api"

/**
 * API client for Maps V2. Domain reads and writes live in ./api/ and are
 * mixed into the prototype, so callers keep using `client.fetchX()`.
 */
export class ApiClient {
  constructor(apiKey, importId = null) {
    this.apiKey = apiKey
    this.baseURL = "/api/v1"
    this.importId = importId
  }

  /**
   * Fetch photos for date range
   */
  async fetchPhotos({ start_at, end_at }) {
    // Photos API uses start_date/end_date parameters
    // Pass dates as-is (matching V1 behavior)
    const params = new URLSearchParams({
      start_date: start_at,
      end_date: end_at,
    })

    maskPrivacyZones(params)
    const url = `${this.baseURL}/photos?${params}`

    const response = await fetch(url, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      Toast.error(translate("messages.failed_to_load_photos"))
      throw new Error(`Failed to fetch photos: ${response.statusText}`)
    }

    const failedSources = response.headers.get("X-Photo-Source-Errors")
    if (failedSources) {
      Toast.warning(
        translate("messages.some_photo_sources_unavailable", {
          sources: failedSources.split(",").join(", "),
        }),
      )
    }

    return response.json()
  }

  /**
   * Fetch the map notes describing a moment in the date range.
   * @returns {Promise<Array>} notes
   */
  async fetchNotes({ start_at, end_at }) {
    const params = new URLSearchParams({ standalone: "true", start_at, end_at })

    maskPrivacyZones(params)
    const response = await fetch(`${this.baseURL}/notes?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch notes: ${response.statusText}`)
    }

    return response.json()
  }

  async fetchVisitedCountries({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })
    if (this.importId) params.set("import_id", this.importId)

    const response = await fetch(
      `${this.baseURL}/countries/visited?${params}`,
      {
        headers: this.getHeaders(),
      },
    )
    if (!response.ok) {
      throw new Error(
        `Failed to fetch visited countries: ${response.statusText}`,
      )
    }

    return response.json()
  }

  /**
   * Fetch timeline day feed for date range
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} { days: [...] }
   */
  async fetchTimeline({ start_at, end_at }) {
    const params = new URLSearchParams({ start_at, end_at })
    maskPrivacyZones(params)

    const response = await fetch(`${this.baseURL}/timeline?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch timeline: ${response.statusText}`)
    }

    return response.json()
  }

  /**
   * Fetch AirTrail flights for a date range as a GeoJSON FeatureCollection.
   * @param {Object} options - { start_at, end_at }
   * @returns {Promise<Object>} GeoJSON FeatureCollection
   */
  async fetchFlights({ start_at, end_at } = {}) {
    const params = new URLSearchParams()
    if (start_at) params.set("start_at", start_at)
    if (end_at) params.set("end_at", end_at)
    maskPrivacyZones(params)

    const response = await fetch(`${this.baseURL}/flights?${params}`, {
      headers: this.getHeaders(),
    })

    if (!response.ok) {
      throw new Error(`Failed to fetch flights: ${response.statusText}`)
    }

    return response.json()
  }

  async fetchPrivacyZones() {
    try {
      const response = await fetch(`${this.baseURL}/tags/privacy_zones`, {
        headers: this.getHeaders(),
      })
      if (!response.ok) return { zones: [], fingerprint: null, failed: true }

      const fingerprint = response.headers.get("X-Privacy-Zones-Fingerprint")
      const zones = (await response.json()).flatMap((zone) =>
        (zone.places || []).map(({ masked_area: area }) => ({
          lon: Number(area.longitude),
          lat: Number(area.latitude),
          radiusMeters: Number(area.radius_meters),
        })),
      )
      return { zones, fingerprint: fingerprint || null }
    } catch {
      return { zones: [], fingerprint: null, failed: true }
    }
  }

  /** Send a write and return its JSON; a failed response throws `failure`. */
  async _send(method, path, failure, body = undefined) {
    const response = await fetch(`${this.baseURL}${path}`, {
      method,
      headers: this.getHeaders(),
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    })

    if (!response.ok) {
      throw new Error(`${failure}: ${response.statusText}`)
    }

    return response.json()
  }

  getHeaders() {
    return {
      Authorization: `Bearer ${this.apiKey}`,
      "Content-Type": "application/json",
    }
  }
}

Object.assign(ApiClient.prototype, pointsApi, tracksApi, visitsPlacesApi)
