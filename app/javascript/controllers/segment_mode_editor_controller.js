import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    segmentId: Number,
    trackId: Number,
    mode: String,
  }

  connect() {
    this.boundHover = this.onMapHover.bind(this)
    document.addEventListener("dawarich:segment-hover", this.boundHover)
    document.addEventListener("dawarich:segment-unhover", this.boundHover)
    this.element.addEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  disconnect() {
    document.removeEventListener("dawarich:segment-hover", this.boundHover)
    document.removeEventListener("dawarich:segment-unhover", this.boundHover)
    this.element.removeEventListener("turbo:submit-end", this.onSubmitEnd)
  }

  submit(event) {
    event.target.form.requestSubmit()
  }

  hover() {
    this.dispatch("segment-hover", {
      detail: {
        segmentId: this.segmentIdValue,
        trackId: this.trackIdValue,
      },
      prefix: "dawarich",
    })
  }

  unhover() {
    this.dispatch("segment-unhover", {
      detail: {
        segmentId: this.segmentIdValue,
        trackId: this.trackIdValue,
      },
      prefix: "dawarich",
    })
  }

  onMapHover(event) {
    const { segmentId, trackId } = event.detail || {}
    if (Number(trackId) !== this.trackIdValue) return
    // Leaving the segments on the map names only the track, so an unhover
    // clears every row of it; a hover highlights just its own row.
    this.element.classList.toggle(
      "highlighted",
      event.type === "dawarich:segment-hover" &&
        segmentId === this.segmentIdValue,
    )
  }

  onSubmitEnd = (event) => {
    if (!event.detail.success) return
    this.dispatch("segment-mode-changed", {
      detail: {
        segmentId: this.segmentIdValue,
        trackId: this.trackIdValue,
        mode: this.modeValue,
      },
      prefix: "dawarich",
    })
  }
}
