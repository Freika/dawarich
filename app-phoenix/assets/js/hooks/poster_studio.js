export const PosterStudio = {
  mounted() {
    this.posterGeneration = 0
    this.posterDestroyed = false
    this.posterOpen = (event) => this.openPoster(event.detail ?? {})
    this.el.addEventListener("dawarich:poster-studio-open", this.posterOpen)
  },
  async openPoster({ source, fallbackBounds }) {
    if (!source) return
    const generation = ++this.posterGeneration
    try {
      const runtime = await (
        this.loader ?? (() => import("../poster/runtime.js"))
      )()
      if (this.posterDestroyed || generation !== this.posterGeneration) return
      this.posterOwner?.destroy()
      this.posterOwner = runtime.mountPosterStudio({
        root: this.el,
        source,
        fallbackBounds,
        pushEvent: this.pushEvent.bind(this),
      })
      await this.posterOwner.open()
    } catch {
      if (!this.posterDestroyed) this.el.dataset.posterState = "failed"
    }
  },
  destroyed() {
    this.posterDestroyed = true
    this.posterGeneration++
    this.el.removeEventListener("dawarich:poster-studio-open", this.posterOpen)
    this.posterOwner?.destroy()
    this.posterOwner = null
  },
}
