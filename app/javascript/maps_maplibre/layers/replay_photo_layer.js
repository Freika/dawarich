import maplibregl from "maplibre-gl"
import { PhotoPopupFactory } from "maps_maplibre/components/photo_popup"

/**
 * Holds replay photos as DOM markers that are revealed one at a time as the
 * replay playhead reaches each photo's timestamp. Markers are created lazily
 * on first reveal (never pre-minted) and pop in with a scale-in animation.
 */
export class ReplayPhotoLayer {
  constructor(map, options = {}) {
    this.map = map
    this.timezone = options.timezone || "UTC"
    this.photos = new Map()
    this.markers = new Map()
    this.revealedIds = new Set()
  }

  setPhotos(photos) {
    this.clear()
    for (const photo of photos || []) {
      if (!this._hasCoordinates(photo)) continue
      this.photos.set(photo.id, photo)
    }
  }

  reveal(id) {
    if (this.markers.has(id)) return
    const photo = this.photos.get(id)
    if (!photo) return

    const marker = this._createMarker(photo)
    if (!marker) return

    this.markers.set(id, marker)
    this.revealedIds.add(id)
  }

  hide(id) {
    const marker = this.markers.get(id)
    if (!marker) return

    marker.remove()
    this.markers.delete(id)
    this.revealedIds.delete(id)
  }

  hideAll() {
    for (const [, marker] of this.markers) marker.remove()
    this.markers.clear()
    this.revealedIds.clear()
  }

  clear() {
    this.hideAll()
    this.photos.clear()
  }

  _hasCoordinates(photo) {
    return (
      photo &&
      photo.id !== undefined &&
      !Number.isNaN(Number(photo.lon)) &&
      !Number.isNaN(Number(photo.lat))
    )
  }

  _createMarker(photo) {
    const lon = Number(photo.lon)
    const lat = Number(photo.lat)
    if (Number.isNaN(lon) || Number.isNaN(lat)) return null

    const el = document.createElement("div")
    el.className = "replay-photo-marker"

    const inner = document.createElement("div")
    inner.className = "replay-photo-marker-inner replay-photo-pop"
    if (photo.thumbnail_url) {
      inner.style.backgroundImage = `url("${encodeURI(photo.thumbnail_url)}")`
    }
    el.appendChild(inner)

    el.addEventListener("click", (event) => {
      event.stopPropagation()
      this._showPopup(photo, lon, lat)
    })

    return new maplibregl.Marker({ element: el, anchor: "center" })
      .setLngLat([lon, lat])
      .addTo(this.map)
  }

  _showPopup(photo, lon, lat) {
    new maplibregl.Popup({
      closeButton: true,
      closeOnClick: true,
      maxWidth: "400px",
    })
      .setLngLat([lon, lat])
      .setHTML(PhotoPopupFactory.createPhotoPopup(photo, this.timezone))
      .addTo(this.map)
  }
}
