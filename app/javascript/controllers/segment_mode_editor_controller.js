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
    if (event.detail.segmentId !== this.segmentIdValue) return
    this.element.classList.toggle(
      "highlighted",
      event.type === "dawarich:segment-hover",
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
