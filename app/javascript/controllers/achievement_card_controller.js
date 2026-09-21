import { Controller } from "@hotwired/stimulus"
import { spectralMarkup } from "achievements/spectral_material"

let uidSequence = 0

function nextUid() {
  uidSequence += 1
  return `sc-${Date.now().toString(36)}-${uidSequence.toString(36)}`
}

// Mount near the viewport; local, frame-coalesced pointer work stays cheap.
export default class extends Controller {
  static targets = ["material"]
  static values = {
    locked: Boolean,
    key: String,
    rarity: String,
    paper: String,
    foil: String,
  }

  connect() {
    this.card = this.element.querySelector(".ach-spectral")
    this.reducedMotion = matchMedia("(prefers-reduced-motion: reduce)")
    // Moving a card into/out of the dialog reconnects this controller before
    // paint. Refit now: IntersectionObserver runs after paint and would expose
    // the previous layout's map scale for a frame before visibly correcting it.
    if (this.mounted || this.element.closest(".ach-modal[open]")) {
      this.mount()
      return
    }
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) this.mount()
      },
      { rootMargin: "160px" },
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
    this.resizeObserver?.disconnect()
    this.leave()
  }

  mount() {
    this.observer?.disconnect()
    // Turbo/dialog moves reconnect the same controller; preserve its material,
    // but observe its new layout so compact cards refit in the fullscreen view.
    if (this.mounted) {
      this.observeSize()
      return
    }

    // Turbo can restore a cached page containing already-generated material
    // into a fresh controller instance. Adopt it instead of looking for the
    // fallback SVG, which was intentionally replaced on first mount.
    if (
      this.materialTarget.querySelector(".geo-stage") &&
      !this.materialTarget.querySelector(".spectral-fallback svg")
    ) {
      this.mounted = true
      this.observeSize()
      return
    }
    const silhouette = this.silhouette
    if (!silhouette) return
    const result = spectralMarkup({
      silhouette,
      key: this.keyValue,
      rarity: this.rarityValue,
      paperAsset: this.paperValue,
      foilAsset: this.foilValue,
      uid: nextUid(),
    })
    if (!result) return
    this.materialTarget.innerHTML = result.html
    this.card.style.setProperty(
      "--accent",
      this.lockedValue ? "#899297" : result.accent,
    )
    this.mounted = true
    this.observeSize()
  }

  get silhouette() {
    const svg = this.materialTarget.querySelector(".spectral-fallback svg")
    const path = svg?.querySelector("path")
    const viewbox = svg?.getAttribute("viewBox")
    const data = path?.getAttribute("d")

    return viewbox && data ? { viewbox, path: data } : null
  }

  observeSize() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.materialTarget.querySelector(".geo-stage"))
    this.fit()
  }

  fit() {
    const stage = this.materialTarget.querySelector(".geo-stage")
    if (!stage?.clientWidth || !stage.clientHeight) return
    const svg = stage.querySelector("svg")
    const box = svg.querySelector(".geo-fill").getBBox()
    const unit = Math.min(stage.clientWidth / 300, stage.clientHeight / 260)
    const width =
      2 * Math.max(Math.abs(box.x - 150), Math.abs(box.x + box.width - 150))
    const height =
      2 * Math.max(Math.abs(box.y - 130), Math.abs(box.y + box.height - 130))
    const scale = Math.max(
      0.05,
      Math.min(
        1.15,
        (stage.clientWidth - 8) / (width * unit),
        (stage.clientHeight - 8) / (height * unit),
      ),
    )
    svg.style.setProperty("--map-scale", scale.toFixed(4))
  }

  move(event) {
    if (
      this.lockedValue ||
      this.reducedMotion.matches ||
      event.pointerType === "touch"
    )
      return
    this.restingRect ||= this.element.getBoundingClientRect()
    this.pointer = { x: event.clientX, y: event.clientY }
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      const rect = this.restingRect
      const x = Math.max(
        -1,
        Math.min(1, ((this.pointer.x - rect.left) / rect.width) * 2 - 1),
      )
      const y = Math.max(
        -1,
        Math.min(1, ((this.pointer.y - rect.top) / rect.height) * 2 - 1),
      )
      this.card.style.setProperty("--rx", `${-y * 10}deg`)
      this.card.style.setProperty("--ry", `${x * 10}deg`)
      this.card.querySelectorAll("[data-spectrum]").forEach((gradient) => {
        gradient.setAttribute(
          "gradientTransform",
          "rotate(" +
            (8 + x * 8 - y * 3) +
            " 150 130) translate(" +
            x * 14 +
            " " +
            y * 8 +
            ")",
        )
      })
    })
  }

  leave() {
    cancelAnimationFrame(this.frame)
    this.frame = null
    this.restingRect = null
    this.card?.style.removeProperty("--rx")
    this.card?.style.removeProperty("--ry")
    this.card?.querySelectorAll("[data-spectrum]").forEach((gradient) => {
      gradient.setAttribute("gradientTransform", "rotate(8 150 130)")
    })
  }
}
