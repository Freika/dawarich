import { Controller } from "@hotwired/stimulus"

// Shows a card with a short loop of the map next to a layer tile while the
// tile is hovered or focused, after a short pause so it does not flicker
// while the pointer crosses the grid. The card is a popover so the scrolling side
// panel cannot clip it; the loop is fetched the first time it is shown.
// Usage: data-controller="layer-preview"
//        data-action="mouseenter->layer-preview#show mouseleave->layer-preview#hide"
//        <div popover="manual" data-layer-preview-target="card"><img data-src="…">
export default class extends Controller {
  static targets = ["card"]

  show() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.open(), 400)
  }

  open() {
    const card = this.cardTarget
    if (!card.showPopover || card.matches(":popover-open")) return
    if (!matchMedia("(hover: hover)").matches) return

    // People who asked for less motion get the description without the loop.
    const image = card.querySelector("img[data-src]")
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) image?.remove()
    else if (image && !image.src) image.src = image.dataset.src
    card.showPopover()

    // Sit right beside the tile, level with it.
    const tile = this.element.getBoundingClientRect()
    const left = tile.right + 8
    const top = Math.min(tile.top, innerHeight - card.offsetHeight - 8)
    card.style.left = `${Math.min(left, innerWidth - card.offsetWidth - 8)}px`
    card.style.top = `${Math.max(8, top)}px`
  }

  hide() {
    clearTimeout(this.timer)
    // Without the Popover API the selector below would throw.
    if (!this.cardTarget.showPopover) return
    if (this.cardTarget.matches(":popover-open")) this.cardTarget.hidePopover()
  }

  disconnect() {
    this.hide()
  }
}
