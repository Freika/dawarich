import maplibregl from "maplibre-gl"
import { PhotoPopupFactory } from "maps_maplibre/components/photo_popup"

const MAX_CARDS = 5

export class ReplayPhotoStack {
  constructor(map, options = {}) {
    this.map = map
    this.timezone = options.timezone || "UTC"
    this.cards = new Map()
    this.container = document.createElement("div")
    this.container.className = "replay-photo-stack"
    this.map.getContainer().appendChild(this.container)
  }

  sync(revealedPhotos) {
    const visible = (revealedPhotos || []).slice(-MAX_CARDS)
    const visibleIds = new Set(visible.map((photo) => photo.id))

    const staleIds = [...this.cards.keys()].filter((id) => !visibleIds.has(id))
    for (const id of staleIds) {
      this.cards.get(id).remove()
      this.cards.delete(id)
    }

    visible.forEach((photo, index) => {
      let card = this.cards.get(photo.id)
      if (!card) {
        card = this._createCard(photo)
        this.container.appendChild(card)
        this.cards.set(photo.id, card)
      }
      const depth = visible.length - 1 - index
      card.style.zIndex = String(index + 1)
      card.style.setProperty("--depth", String(depth))
    })
  }

  clear() {
    for (const [, card] of this.cards) card.remove()
    this.cards.clear()
  }

  destroy() {
    this.clear()
    this.container.remove()
  }

  _createCard(photo) {
    const card = document.createElement("div")
    card.className = "replay-photo-stack-card replay-photo-stack-pop"
    card.style.setProperty("--rot", `${this._rotation(photo.id)}deg`)

    const img = document.createElement("div")
    img.className = "replay-photo-stack-img"
    if (photo.thumbnail_url) {
      img.style.backgroundImage = `url("${encodeURI(photo.thumbnail_url)}")`
    }
    card.appendChild(img)

    card.addEventListener("click", (event) => {
      event.stopPropagation()
      this._showPopup(photo)
    })
    return card
  }

  _rotation(id) {
    const str = String(id)
    let hash = 0
    for (let i = 0; i < str.length; i++) {
      hash = (hash * 31 + str.charCodeAt(i)) | 0
    }
    const norm = (Math.abs(hash) % 1000) / 1000
    return (norm * 10 - 5).toFixed(2)
  }

  _showPopup(photo) {
    const lon = Number(photo.lon)
    const lat = Number(photo.lat)
    if (Number.isNaN(lon) || Number.isNaN(lat)) return

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
