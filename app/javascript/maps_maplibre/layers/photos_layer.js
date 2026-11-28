import { translate } from "i18n"
import * as maplibregl from "maplibre-gl"
import { PhotoClusterGallery } from "../components/photo_cluster_gallery"
import {
  escapeAttribute,
  escapeHtml,
  formatTimestamp,
} from "../utils/geojson_transformers"
import { getCurrentTheme, getThemeColors } from "../utils/popup_theme"
import { BaseLayer } from "./base_layer"
import { photoSpider } from "./photos/spider"

/**
 * Photos layer with clustering and thumbnail markers
 * Uses MapLibre's built-in GeoJSON clustering for cluster circles,
 * and DOM markers with thumbnail images for individual (unclustered) photos.
 */
export class PhotosLayer extends BaseLayer {
  constructor(map, options = {}) {
    super(map, { id: "photos", ...options })
    this.timezone = options.timezone || "UTC"
    this.markerCache = new Map() // keyed by feature id for efficient reuse
    this.legCache = new Map() // spider leg layer ids keyed by feature id
    this._syncMarkers = this._syncMarkers.bind(this)
    this._onClusterClick = this._onClusterClick.bind(this)
    this._onMoveEnd = this._onMoveEnd.bind(this)
    this._onClusterEnter = () => {
      this.map.getCanvas().style.cursor = "pointer"
    }
    this._onClusterLeave = () => {
      this.map.getCanvas().style.cursor = ""
    }
    this._closeGallery = this._closeGallery.bind(this)
    this._onKeyDown = (event) => {
      if (event.key !== "Enter" || !this.visible) return
      const canvas = this.map.getCanvas()
      const center = { x: canvas.clientWidth / 2, y: canvas.clientHeight / 2 }
      const features = this.map.queryRenderedFeatures({
        layers: ["photos-clusters"],
      })
      features.sort((a, b) => {
        const distance = (feature) => {
          const point = this.map.project(feature.geometry.coordinates)
          return Math.hypot(point.x - center.x, point.y - center.y)
        }
        return distance(a) - distance(b)
      })
      if (features.length) {
        event.preventDefault()
        this._openCluster(features[0])
      }
    }
    this._onStyleData = () => {
      if (
        this.gallery &&
        this.map.getSource(this.sourceId) !== this.gallerySource
      ) {
        this._closeGallery()
      }
    }
    this._onSourceData = (event) => {
      if (event.sourceId === this.sourceId && event.isSourceLoaded) {
        this._syncMarkers()
      }
    }
  }

  getSourceConfig() {
    return {
      type: "geojson",
      data: this.data || { type: "FeatureCollection", features: [] },
      cluster: true,
      clusterRadius: 60,
      // Keep identical coordinates browsable throughout the map zoom range.
      maxzoom: 24,
      clusterMaxZoom: 23,
    }
  }

  getLayerConfigs() {
    return [
      {
        id: "photos-clusters",
        type: "circle",
        source: this.sourceId,
        filter: ["has", "point_count"],
        paint: {
          "circle-color": "rgba(59, 130, 246, 0.7)",
          "circle-radius": [
            "step",
            ["get", "point_count"],
            20, // default radius
            10,
            25, // >= 10 photos
            50,
            30, // >= 50 photos
          ],
          "circle-stroke-width": 2,
          "circle-stroke-color": "#ffffff",
        },
      },
      {
        id: "photos-cluster-count",
        type: "symbol",
        source: this.sourceId,
        filter: ["has", "point_count"],
        layout: {
          "text-field": "{point_count_abbreviated}",
          "text-size": 14,
          "text-allow-overlap": true,
        },
        paint: {
          "text-color": "#ffffff",
        },
      },
    ]
  }

  getLayerIds() {
    return ["photos-clusters", "photos-cluster-count"]
  }

  // Stack cluster counts over circles, directly above the given layer, so
  // layers that already sit higher (live and replay markers) stay on top.
  raiseAbove(layerId) {
    const ownIds = this.getLayerIds()
    const otherIds = (this.map.getStyle?.()?.layers ?? [])
      .map((layer) => layer.id)
      .filter((id) => !ownIds.includes(id))
    const index = otherIds.indexOf(layerId)
    const beforeId = index === -1 ? undefined : otherIds[index + 1]
    for (const id of ownIds) {
      if (this.map.getLayer(id)) this.map.moveLayer(id, beforeId)
    }
  }

  async add(data) {
    this.data = data

    // Register source and cluster layers via BaseLayer
    super.add(data)

    // Cluster click → bounded gallery
    this.map.on("click", "photos-clusters", this._onClusterClick)

    // Cursor changes on cluster hover
    this.map.on("mouseenter", "photos-clusters", this._onClusterEnter)
    this.map.on("mouseleave", "photos-clusters", this._onClusterLeave)

    const canvas = this.map.getCanvas()
    this._canvasDescription = canvas.getAttribute("aria-description")
    canvas.setAttribute(
      "aria-description",
      translate("photo_cluster.keyboard_hint"),
    )
    canvas.addEventListener("keydown", this._onKeyDown)
    this.map.on("styledata", this._onStyleData)
    this.map.on("remove", this._closeGallery)

    // Sync DOM markers when data loads or map moves
    this.map.on("moveend", this._onMoveEnd)

    // Also sync when source data finishes loading
    this.map.on("data", this._onSourceData)

    // Initial sync
    this._syncMarkers()
  }

  async update(data) {
    this._closeGallery()
    this.data = data
    const source = this.map.getSource(this.sourceId)
    if (source?.setData) {
      source.setData(data)
    }
    // Markers will sync via the data event
  }

  _onMoveEnd() {
    this._syncMarkers()
  }

  _onClusterClick(e) {
    const features = this.map.queryRenderedFeatures(e.point, {
      layers: ["photos-clusters"],
    })
    if (!features.length) return

    this._openCluster(features[0])
  }

  _closeGallery() {
    this.gallery?.close()
    this.gallery = null
    this.gallerySource = null
  }

  _openCluster(feature) {
    const source = this.map.getSource(this.sourceId)
    if (!source || !this.visible) return
    const { cluster_id: clusterId, point_count: total } = feature.properties
    this._closeGallery()
    this.gallerySource = source
    this.gallery = new PhotoClusterGallery({
      total,
      timezone: this.timezone,
      returnFocus: this.map.getCanvas(),
      loadPage: (limit, offset) =>
        source.getClusterLeaves(clusterId, limit, offset),
      onClose: () => {
        this.gallery = null
        this.gallerySource = null
      },
    }).open()
  }

  /**
   * Sync DOM markers to currently visible unclustered photo features.
   * Creates new markers, reuses cached ones, removes stale ones,
   * and spreads overlapping markers in a circle (spiderfier).
   */
  _syncMarkers() {
    if (!this.visible) return

    const source = this.map.getSource(this.sourceId)
    if (!source) return

    // Query unclustered features from the source
    const features = this.map.querySourceFeatures(this.sourceId, {
      filter: ["!", ["has", "point_count"]],
    })

    // Deduplicate by feature id (querySourceFeatures can return dupes across tiles)
    const seen = new Map()
    for (const feature of features) {
      const id =
        feature.properties.id ||
        `${feature.geometry.coordinates[0]}_${feature.geometry.coordinates[1]}`
      if (!seen.has(id)) {
        seen.set(id, feature)
      }
    }

    // Filter to current viewport
    const bounds = this.map.getBounds()
    const visibleFeatures = new Map()
    for (const [id, feature] of seen) {
      const [lng, lat] = feature.geometry.coordinates
      if (bounds.contains([lng, lat])) {
        visibleFeatures.set(id, feature)
      }
    }

    // Compute spiderfied positions for overlapping markers
    const offsets = this._computeSpiderOffsets(visibleFeatures)

    // Remove markers and legs no longer visible
    for (const [id, marker] of this.markerCache) {
      if (!visibleFeatures.has(id)) {
        marker.remove()
        this.markerCache.delete(id)
        this._removeLeg(id)
      }
    }

    // Add or update markers and legs
    for (const [id, feature] of visibleFeatures) {
      const offset = offsets.get(id)
      const origin = this._originalCoordinates(feature)

      if (this.markerCache.has(id)) {
        if (offset) {
          // Update marker position and leg
          this.markerCache.get(id).setLngLat(offset)
          this._updateLeg(id, origin, offset)
        } else {
          // No longer offset — reset to original position, remove leg
          this.markerCache.get(id).setLngLat(origin)
          this._removeLeg(id)
        }
      } else {
        const lngLat = offset || origin
        const marker = this._createPhotoMarker(feature, lngLat)
        this.markerCache.set(id, marker)
        if (offset) {
          this._updateLeg(id, origin, offset)
        }
      }
    }
  }

  /**
   * Create a single DOM marker for a photo feature
   * @param {Object} feature - GeoJSON feature
   * @param {Array} lngLat - [lng, lat] position (may be offset from original)
   */
  _createPhotoMarker(feature, lngLat) {
    const { thumbnail_url } = feature.properties
    const [lng, lat] = lngLat || feature.geometry.coordinates

    const container = document.createElement("div")
    container.style.display = this.visible ? "block" : "none"

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

    el.addEventListener("click", (e) => {
      e.stopPropagation()
      this.showPhotoPopup(feature)
    })

    container.appendChild(el)

    const marker = new maplibregl.Marker({ element: container })
      .setLngLat([lng, lat])
      .addTo(this.map)

    return marker
  }

  /**
   * Show photo popup with image
   * @param {Object} feature - GeoJSON feature with photo properties
   */
  showPhotoPopup(feature) {
    this._closeGallery()
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
    const [lng, lat] = this._originalCoordinates(feature)

    const takenDate = taken_at
      ? formatTimestamp(taken_at, this.timezone)
      : translate("common.unknown")
    const location =
      [city, state, country].filter(Boolean).join(", ") ||
      translate("search.unknown_location")
    const mediaType =
      type === "VIDEO"
        ? `🎥 ${translate("map_info.video")}`
        : `📷 ${translate("map_info.photo")}`

    // Get theme colors
    const theme = getCurrentTheme()
    const colors = getThemeColors(theme)

    // Create popup HTML with theme-aware styling
    const popupHTML = `
      <div class="photo-popup" style="font-family: system-ui, -apple-system, sans-serif; max-width: 350px;">
        <div style="width: 100%; border-radius: 8px; overflow: hidden; margin-bottom: 12px; background: ${colors.backgroundAlt};">
          <img
            src="${escapeAttribute(thumbnail_url)}"
            alt="${escapeAttribute(filename || translate("map_info.photo"))}"
            style="width: 100%; height: auto; max-height: 350px; object-fit: contain; display: block;"
            loading="lazy"
          />
        </div>
        <div style="font-size: 13px;">
          ${filename ? `<div style="font-weight: 600; color: ${colors.textPrimary}; margin-bottom: 6px; word-wrap: break-word;">${escapeHtml(filename)}</div>` : ""}
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📅 ${takenDate}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">📍 ${escapeHtml(location)}</div>
          <div style="color: ${colors.textMuted}; font-size: 12px; margin-bottom: 6px;">${translate("map_info.coordinates")}: ${lat.toFixed(6)}, ${lng.toFixed(6)}</div>
          ${source ? `<div style="color: ${colors.textSecondary}; font-size: 11px; margin-bottom: 6px;">${translate("map_info.source")}: ${escapeHtml(source)}</div>` : ""}
          <div style="font-size: 14px; margin-top: 8px; color: ${colors.textPrimary};">${mediaType}</div>
        </div>
      </div>
    `

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
   * Clear all cached DOM markers from map
   */
  clearMarkers() {
    for (const [, marker] of this.markerCache) {
      marker.remove()
    }
    this.markerCache.clear()
    this._clearAllLegs()
  }

  /**
   * Show cluster layers and all cached DOM markers
   */
  show() {
    this.visible = true
    this.setVisibility(true)
    for (const [, marker] of this.markerCache) {
      marker.getElement().style.display = "block"
    }
    for (const [, legId] of this.legCache) {
      if (this.map.getLayer(legId)) {
        this.map.setLayoutProperty(legId, "visibility", "visible")
      }
    }
    // Re-sync to pick up any features that should now be visible
    this._syncMarkers()
  }

  /**
   * Hide cluster layers and all cached DOM markers
   */
  hide() {
    this._closeGallery()
    this.visible = false
    this.setVisibility(false)
    for (const [, marker] of this.markerCache) {
      marker.getElement().style.display = "none"
    }
    for (const [, legId] of this.legCache) {
      if (this.map.getLayer(legId)) {
        this.map.setLayoutProperty(legId, "visibility", "none")
      }
    }
  }

  /**
   * Remove layer, clean up markers and event listeners
   */
  remove() {
    this._closeGallery()
    const canvas = this.map.getCanvas()
    canvas.removeEventListener("keydown", this._onKeyDown)
    if (this._canvasDescription == null)
      canvas.removeAttribute("aria-description")
    else canvas.setAttribute("aria-description", this._canvasDescription)
    this.map.off("styledata", this._onStyleData)
    this.map.off("remove", this._closeGallery)
    this.clearMarkers()
    this.map.off("moveend", this._onMoveEnd)
    this.map.off("click", "photos-clusters", this._onClusterClick)
    this.map.off("mouseenter", "photos-clusters", this._onClusterEnter)
    this.map.off("mouseleave", "photos-clusters", this._onClusterLeave)
    this.map.off("data", this._onSourceData)
    super.remove()
  }
}

Object.assign(PhotosLayer.prototype, photoSpider)
