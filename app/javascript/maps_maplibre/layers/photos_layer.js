import maplibregl from "maplibre-gl"
import { getCurrentTheme, getThemeColors } from "../utils/popup_theme"
import { BaseLayer } from "./base_layer"

/**
 * Photos layer with thumbnail markers
 * Uses HTML DOM markers with circular image thumbnails
 */
export class PhotosLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "photos", ...options })
    this.markers = [] // Store marker references for cleanup
    this.timezone = options.timezone || "UTC"
  }

  async add(data) {
    console.log("[PhotosLayer] add() called with data:", {
      featuresCount: data.features?.length || 0,
      sampleFeature: data.features?.[0],
      visible: this.visible,
    })

    // Store data
    this.data = data

    // Create HTML markers for photos
    this.createPhotoMarkers(data)
    console.log("[PhotosLayer] Photo markers created")
  }

  async update(data) {
    console.log("[PhotosLayer] update() called with data:", {
      featuresCount: data.features?.length || 0,
    })

    // Remove existing markers
    this.clearMarkers()

    // Create new markers
    this.createPhotoMarkers(data)
    console.log("[PhotosLayer] Photo markers updated")
  }

  /**
   * Create HTML markers with photo thumbnails
   * @param {Object} geojson - GeoJSON with photo features
   */
  createPhotoMarkers(geojson) {
    if (!geojson?.features) {
      console.log("[PhotosLayer] No features to create markers for")
      return
    }

    console.log(
      "[PhotosLayer] Creating markers for",
      geojson.features.length,
      "photos",
    )
    console.log("[PhotosLayer] Sample feature:", geojson.features[0])

    geojson.features.forEach((feature, index) => {
      const { id, thumbnail_url, photo_url, taken_at } = feature.properties
      const [lng, lat] = feature.geometry.coordinates

      if (index === 0) {
        console.log("[PhotosLayer] First marker thumbnail_url:", thumbnail_url)
      }

      // Create marker container (MapLibre will position this)
      const container = document.createElement("div")
      container.style.cssText = `
        display: ${this.visible ? "block" : "none"};
      `

      // Create inner element for the image (this is what we'll transform)
      const el = document.createElement("div")
      el.className = "photo-marker"
      el.style.cssText = `
        width: 50px;
        height: 50px;
        border-radius: 50%;
        cursor: pointer;
        background-size: cover;
        background-position: center;
        background-image: url('${thumbnail_url}');
        border: 3px solid white;
        box-shadow: 0 2px 4px rgba(0,0,0,0.3);
        transition: transform 0.2s, box-shadow 0.2s;
      `

      // Add hover effect
      el.addEventListener("mouseenter", () => {
        el.style.transform = "scale(1.2)"
        el.style.boxShadow = "0 4px 8px rgba(0,0,0,0.4)"
        el.style.zIndex = "1000"
      })

      el.addEventListener("mouseleave", () => {
        el.style.transform = "scale(1)"
        el.style.boxShadow = "0 2px 4px rgba(0,0,0,0.3)"
        el.style.zIndex = "1"
      })

      // Add click handler to show popup
      el.addEventListener("click", (e) => {
        e.stopPropagation()
        this.showPhotoPopup(feature)
      })

      // Add image element to container
      container.appendChild(el)

      // Create MapLibre marker with container
      const marker = new maplibregl.Marker({ element: container })
        .setLngLat([lng, lat])
        .addTo(this.map)

      this.markers.push(marker)

      if (index === 0) {
        console.log("[PhotosLayer] First marker created at:", lng, lat)
      }
    })

    console.log(
      "[PhotosLayer] Created",
      this.markers.length,
      "markers, visible:",
      this.visible,
    )
  }

  /**
   * Show photo popup with image
   * @param {Object} feature - GeoJSON feature with photo properties
   */
  showPhotoPopup(feature) {
    const {
      thumbnail_url,
      taken_at,
      filename,
      city,
      state,
      country,
      type,
      source,
    } = feature.properties
    const [lng, lat] = feature.geometry.coordinates

    const takenDate = taken_at
      ? new Date(taken_at).toLocaleString(undefined, {
          timeZone: this.timezone,
        })
      : "Unknown"
    const location =
      [city, state, country].filter(Boolean).join(", ") || "Unknown location"
    const mediaType = type === "VIDEO" ? "🎥 Video" : "📷 Photo"

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    // Create popup HTML with theme-aware styling
    const popupHTML = `
      <div class="photo-popup" style="font-family: system-ui, -apple-system, sans-serif; max-width: 350px;">
        <div style="width: 100%; border-radius: 8px; overflow: hidden; margin-bottom: 12px; background: ${colors.backgroundAlt};">
          <img
            src="${thumbnail_url}"
            alt="${filename || "Photo"}"
            style="width: 100%; height: auto; max-height: 350px; object-fit: contain; display: block;"
            loading="lazy"
          />
        </div>
        <div style="font-size: 13px;">
          ${filename ? `<div style="font-weight: 600; color: ${colors.textPrimary}; margin-bottom: 6px; word-wrap: break-word;">${filename}</div>` : ""}
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📅 ${takenDate}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📍 ${location}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">Coordinates: ${lat.toFixed(6)}, ${lng.toFixed(6)}</div>
          ${source ? `<div style="color: ${colors.textSecondary}; font-size: 11px; margin-bottom: 6px;">Source: ${source}</div>` : ""}
          <div style="font-size: 14px; margin-top: 8px; color: ${colors.textPrimary};">${mediaType}</div>
        </div>
      </div>
    `

    // Create and show popup
    new maplibregl.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: "400px",
    })
      .setLngLat([lng, lat])
      .setHTML(popupHTML)
      .addTo(this.map)
  }

  /**
   * Clear all markers from map
   */
  clearMarkers() {
    this.markers.forEach((marker) => {
      marker.remove()
    })
    this.markers = []
  }

  /**
   * Override remove to clean up markers
   */
  remove() {
    this.clearMarkers()
    super.remove()
  }

  /**
   * Override show to display markers
   */
  show() {
    this.visible = true
    this.markers.forEach((marker) => {
      marker.getElement().style.display = "block"
    })
  }

  /**
   * Override hide to hide markers
   */
  hide() {
    this.visible = false
    this.markers.forEach((marker) => {
      marker.getElement().style.display = "none"
    })
  }

  // Override these methods since we're not using source/layer approach
  getSourceConfig() {
    return null
  }

  getLayerConfigs() {
    return []
  }

  getLayerIds() {
    return []
  }
}
