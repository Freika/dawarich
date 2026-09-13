import { Controller } from "@hotwired/stimulus"

// Swatch-grid theme picker for the poster form. Click selects (writes the
// hidden poster[theme] field); hovering a swatch live-updates the preview
// slot, which reverts to the selected theme on mouse-leave.
export default class extends Controller {
  static targets = [
    "input",
    "swatch",
    "previewMock",
    "previewImage",
    "previewName",
    "previewDescription",
  ]

  connect() {
    const current = this.inputTarget.value
    const initial =
      this.swatchTargets.find((s) => s.dataset.key === current) ||
      this.swatchTargets[0]
    if (initial) this.choose(initial)
  }

  select(event) {
    this.choose(event.currentTarget)
  }

  preview(event) {
    this.render(event.currentTarget)
  }

  restorePreview() {
    const selected = this.swatchTargets.find(
      (s) => s.dataset.key === this.selectedKey,
    )
    if (selected) this.render(selected)
  }

  choose(swatch) {
    this.selectedKey = swatch.dataset.key
    this.inputTarget.value = this.selectedKey
    for (const s of this.swatchTargets) {
      const on = s === swatch
      s.classList.toggle("ring-2", on)
      s.classList.toggle("ring-offset-1", on)
      s.setAttribute("aria-pressed", on ? "true" : "false")
    }
    this.render(swatch)
    document.dispatchEvent(
      new CustomEvent("poster-theme:changed", {
        detail: { key: this.selectedKey },
      }),
    )
  }

  render(swatch) {
    const { bg, route, name, description, thumb } = swatch.dataset
    if (this.hasPreviewMockTarget) {
      this.previewMockTarget.style.background = `linear-gradient(135deg, ${bg} 0 40%, ${route} 40% 56%, ${bg} 56% 100%)`
    }
    if (this.hasPreviewImageTarget) {
      this.previewImageTarget.src = thumb || ""
    }
    if (this.hasPreviewNameTarget) {
      this.previewNameTarget.textContent = name
    }
    if (this.hasPreviewDescriptionTarget) {
      this.previewDescriptionTarget.textContent = description
    }
  }
}
