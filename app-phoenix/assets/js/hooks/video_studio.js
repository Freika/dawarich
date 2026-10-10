const REPLY_TIMEOUT_MS = 30_000

export const VideoStudio = {
  mounted() {
    this.videoGeneration = 0
    this.videoDestroyed = false
    this.videoOpen = (event) => this.openVideo(event.detail ?? {})
    this.el.addEventListener("dawarich:video-studio-open", this.videoOpen)
  },
  async openVideo({ source, recipe }) {
    if (!source) return
    const generation = ++this.videoGeneration
    try {
      const runtime = await (
        this.loader ?? (() => import("../video/studio.js"))
      )()
      if (this.videoDestroyed || generation !== this.videoGeneration) return
      if (this.videoSource !== source) {
        this.videoOwner?.destroy()
        this.videoSource = source
        this.videoOwner = runtime.mountVideoStudio({
          root: this.el,
          source,
          request: (event, payload) => this.videoRequest(event, payload),
        })
      }
      await this.videoOwner.open(recipe)
    } catch {
      if (!this.videoDestroyed) this.el.dataset.videoState = "failed"
    }
  },
  videoRequest(event, payload) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error("No reply")),
        REPLY_TIMEOUT_MS,
      )
      this.pushEventTo(this.el, event, payload, (reply) => {
        clearTimeout(timer)
        resolve(reply)
      })
    })
  },
  destroyed() {
    this.videoDestroyed = true
    this.videoGeneration++
    this.el.removeEventListener("dawarich:video-studio-open", this.videoOpen)
    this.videoOwner?.destroy()
    this.videoOwner = null
    this.videoSource = null
  },
}
