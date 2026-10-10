export const PosterStudio = {
  mounted() {
    this.posterGeneration = 0
    this.posterDestroyed = false
    this.posterOpen = (event) => this.openPoster(event.detail ?? {})
    this.el.addEventListener("dawarich:poster-studio-open", this.posterOpen)
  },
  async openPoster({ source, fallbackBounds, openVideo }) {
    if (!source) return
    const generation = ++this.posterGeneration
    try {
      if (this.posterOwner && source === this.posterSource)
        return await this.posterOwner.open()
      const runtime = await (
        this.loader ?? (() => import("../poster/runtime.js"))
      )()
      if (this.posterDestroyed || generation !== this.posterGeneration) return
      this.posterOwner?.destroy()
      this.posterOwner = runtime.mountPosterStudio({
        root: this.el,
        source,
        fallbackBounds,
        openVideo,
        pushEvent: this.pushEvent.bind(this),
      })
      this.posterSource = source
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
    this.posterSource = null
  },
}
