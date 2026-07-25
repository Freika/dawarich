import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    tilt: { type: Number, default: 12 },
    holo: { type: Number, default: 0.7 },
    locked: { type: Boolean, default: false },
  }

  move(event) {
    if (this.lockedValue) return

    const rect = this.element.getBoundingClientRect()
    const px = (event.clientX - rect.left) / rect.width
    const py = (event.clientY - rect.top) / rect.height

    this.element.style.setProperty(
      "--ry",
      `${((px - 0.5) * 2 * this.tiltValue).toFixed(2)}deg`,
    )
    this.element.style.setProperty(
      "--rx",
      `${((0.5 - py) * 2 * this.tiltValue).toFixed(2)}deg`,
    )
    this.element.style.setProperty("--mx", `${(px * 100).toFixed(1)}%`)
    this.element.style.setProperty("--my", `${(py * 100).toFixed(1)}%`)
    this.element.style.setProperty("--fo", String(this.holoValue))
    this.element.style.setProperty("--sc", "1.04")
    this.element.style.setProperty("--gl", "1")
  }

  leave() {
    for (const prop of [
      "--ry",
      "--rx",
      "--mx",
      "--my",
      "--fo",
      "--sc",
      "--gl",
    ]) {
      this.element.style.removeProperty(prop)
    }
  }
}
