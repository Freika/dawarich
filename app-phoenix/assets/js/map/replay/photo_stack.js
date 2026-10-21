import { createReplayPhotoCard } from "./photo_card.js"
import { stackLeftOffset } from "./photo_offset.js"

export class ReplayPhotoStack {
  constructor(options) {
    this.options = options
    this.container = options.container
    this.cards = new Map()
    this.destroyed = false
  }
  sync(photos) {
    if (this.destroyed) return
    const visible = photos.slice(-5),
      ids = new Set(visible.map((photo) => photo.id))
    for (const [id, card] of this.cards)
      if (!ids.has(id)) {
        card.remove()
        this.cards.delete(id)
      }
    const root = this.container.closest?.("[data-native-map-root]")
    const cluster = root?.querySelector("[data-map-tools]")
    const containerRect = this.container.getBoundingClientRect?.() ?? {
      left: 0,
    }
    const left = stackLeftOffset({
      container: containerRect,
      cluster: cluster?.getBoundingClientRect(),
    })
    visible.forEach((photo, index) => {
      let card = this.cards.get(photo.id)
      if (!card) {
        card = createReplayPhotoCard({ ...this.options, photo })
        this.cards.set(photo.id, card)
        this.container.appendChild(card.element)
      }
      const depth = visible.length - 1 - index
      card.element.style.zIndex = String(index + 1)
      card.element.style.left = `${left + depth * 8}px`
      card.element.style.transform = `rotate(${this.rotation(photo.id)}deg)`
    })
  }
  rotation(id) {
    let hash = 0
    for (const char of String(id)) hash = (hash * 31 + char.charCodeAt(0)) | 0
    return (((Math.abs(hash) % 1000) / 1000) * 10 - 5).toFixed(2)
  }
  clear() {
    for (const card of this.cards.values()) card.remove()
    this.cards.clear()
    this.container.replaceChildren()
  }
  destroy() {
    this.destroyed = true
    this.clear()
  }
  get ready() {
    return Promise.all([...this.cards.values()].map((card) => card.ready))
  }
}
