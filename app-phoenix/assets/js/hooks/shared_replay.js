import { PublicDayClock } from "./shared_day_clock.js"

export class PublicReplay {
  constructor(root, map, library, points, zone, locale) {
    this.root = root
    this.map = map
    this.library = library
    this.zone = zone
    this.locale = locale
    this.clock = new PublicDayClock(zone, locale)
    this.panel = root.querySelector("[data-public-replay-panel]")
    this.speed = 2
    this.follow = false
    this.timer = null
    this.day = 0
    this.index = 0
    const groups = new Map()
    for (const point of points) {
      const date = this.clock.key(this.clock.parts(point[2] * 1000))
      if (!groups.has(date)) groups.set(date, [])
      groups.get(date).push(point)
    }
    this.days = [...groups].sort().map(([date, rows]) => {
      const points = rows.sort((a, b) => a[2] - b[2])
      const minutes = points.map((point) => this.clock.minute(point))
      const buckets = new Map()
      const positions = []
      minutes.forEach((minute, index) => {
        if (!buckets.has(minute)) buckets.set(minute, [])
        positions.push(buckets.get(minute).length)
        buckets.get(minute).push(index)
      })
      return { date, points, minutes, buckets, positions }
    })
  }
  target(name) {
    return this.root.querySelector(`[data-public-replay-target="${name}"]`)
  }
  text(name, value) {
    const el = this.target(name)
    if (el) el.textContent = value
  }
  hidden(name, value) {
    this.target(name)?.classList.toggle("hidden", value)
  }
  pause() {
    clearInterval(this.timer)
    this.timer = null
    this.hidden("replayPlayIcon", false)
    this.hidden("replayPauseIcon", true)
  }
  minute() {
    return this.days[this.day].minutes[this.index]
  }
  current() {
    return this.days[this.day]?.points || []
  }
  draw() {
    const rows = this.current()
    const point = rows[this.index]
    if (!point) return
    if (!this.marker)
      this.marker = new this.library.Marker()
        .setLngLat(point.slice(0, 2))
        .addTo(this.map)
    this.marker.setLngLat(point.slice(0, 2))
    if (this.follow)
      this.map.easeTo({ center: point.slice(0, 2), duration: 100 })
    const minute = this.minute()
    this.text("replayTimeDisplay", this.clock.label(point))
    this.text(
      "replayDayDisplay",
      this.clock.formats.day.format(new Date(point[2] * 1000)),
    )
    this.text("replayDayCount", `${this.day + 1} / ${this.days.length}`)
    const scrubber = this.target("replayScrubber")
    if (scrubber) {
      scrubber.value = String(minute)
      scrubber.max = String(this.clock.day(this.days[this.day].date).length - 1)
    }
    const day = this.days[this.day]
    const same = day.buckets.get(minute)
    this.hidden("replayCycleControls", same.length < 2)
    this.text(
      "replayPointCounter",
      `${day.positions[this.index] + 1} / ${same.length}`,
    )
    const previous = this.target("replayPrevDayButton"),
      next = this.target("replayNextDayButton")
    if (previous) previous.disabled = this.day === 0
    if (next) next.disabled = this.day === this.days.length - 1
  }
  action(name, value) {
    if (!this.panel || !this.days.length) return
    if (name === "toggleReplay") {
      this.panel.hidden = !this.panel.hidden
      this.panel.classList.toggle("hidden", this.panel.hidden)
      if (this.panel.hidden) {
        this.pause()
        this.marker?.remove()
        this.marker = null
      } else this.draw()
    } else if (name === "replayTogglePlayback") {
      if (this.timer) this.pause()
      else {
        if (this.index === this.current().length - 1) this.index = 0
        this.hidden("replayPlayIcon", true)
        this.hidden("replayPauseIcon", false)
        this.timer = setInterval(() => {
          if (!this.days.length || this.index >= this.current().length - 1)
            return this.pause()
          this.index++
          this.draw()
        }, 1000 / this.speed)
      }
    } else if (name === "replaySpeedChange") {
      const running = Boolean(this.timer)
      this.pause()
      this.speed = [1, 2, 5, 10][Number(value) - 1] || 2
      this.text("replaySpeedLabel", `${this.speed}x`)
      if (running) this.action("replayTogglePlayback")
    } else if (name === "replayScrubberHover") {
      this.pause()
      const minutes = this.days[this.day].minutes
      const wanted = Number(value)
      let lo = 0,
        hi = minutes.length
      while (lo < hi) {
        const middle = Math.floor((lo + hi) / 2)
        if (minutes[middle] < wanted) lo = middle + 1
        else hi = middle
      }
      const next = Math.min(lo, minutes.length - 1)
      const previous = Math.max(0, lo - 1)
      const minute =
        Math.abs(minutes[next] - wanted) < Math.abs(minutes[previous] - wanted)
          ? minutes[next]
          : minutes[previous]
      this.index = this.days[this.day].buckets.get(minute)[0]
      this.draw()
    } else if (name === "replayRecenterFollow") {
      this.follow = !this.follow
      this.draw()
    } else if (name === "replayPrevDay" || name === "replayNextDay") {
      this.pause()
      this.day = Math.max(
        0,
        Math.min(
          this.days.length - 1,
          this.day + (name === "replayNextDay" ? 1 : -1),
        ),
      )
      this.index = 0
      this.draw()
    } else if (name === "replayCyclePrev" || name === "replayCycleNext") {
      this.pause()
      const day = this.days[this.day]
      const bucket = day.buckets.get(day.minutes[this.index])
      const position =
        day.positions[this.index] + (name === "replayCycleNext" ? 1 : -1)
      if (bucket[position] !== undefined) this.index = bucket[position]
      this.draw()
    }
  }
  clear() {
    this.pause()
    this.marker?.remove()
    this.marker = null
    this.days = []
    this.clock.clear()
    this.map = null
    if (this.panel) {
      this.panel.hidden = true
      this.panel.classList.toggle("hidden", true)
    }
    for (const name of [
      "replayDayDisplay",
      "replayDayCount",
      "replayTimeDisplay",
      "replayPointCounter",
    ])
      this.text(name, "")
  }
}
