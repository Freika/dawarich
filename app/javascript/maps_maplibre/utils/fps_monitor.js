/**
 * FPS (Frames Per Second) monitor
 * Tracks rendering performance
 */
export class FPSMonitor {
  constructor(sampleSize = 60) {
    this.sampleSize = sampleSize
    this.frames = []
    this.lastTime = performance.now()
    this.isRunning = false
    this.rafId = null
  }

  start() {
    if (this.isRunning) return
    this.isRunning = true
    this.#tick()
  }

  stop() {
    this.isRunning = false
    if (this.rafId) {
      cancelAnimationFrame(this.rafId)
      this.rafId = null
    }
  }

  getFPS() {
    if (this.frames.length === 0) return 0
    const avg = this.frames.reduce((a, b) => a + b, 0) / this.frames.length
    return Math.round(avg)
  }

  #tick = () => {
    if (!this.isRunning) return

    const now = performance.now()
    const delta = now - this.lastTime
    const fps = 1000 / delta

    this.frames.push(fps)
    if (this.frames.length > this.sampleSize) {
      this.frames.shift()
    }

    this.lastTime = now
    this.rafId = requestAnimationFrame(this.#tick)
  }
}
