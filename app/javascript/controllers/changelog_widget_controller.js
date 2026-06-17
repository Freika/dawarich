import { Controller } from "@hotwired/stimulus"

// Injects the chibichange loader on connect so the new-version dot mounts even
// when this element arrives via a Turbo Stream (inline <script> tags delivered
// in stream responses never execute). The loader discovers #chgtool-mount.
export default class extends Controller {
  static values = { src: String, slug: String, version: String }

  connect() {
    if (document.getElementById("chibichange-loader")) return

    const script = document.createElement("script")
    script.id = "chibichange-loader"
    script.src = this.srcValue
    script.async = true
    script.dataset.slug = this.slugValue
    script.dataset.version = this.versionValue
    script.dataset.consent = "granted"
    script.dataset.mount = "#chgtool-mount"
    document.head.appendChild(script)
  }
}
