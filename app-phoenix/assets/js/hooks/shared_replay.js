export class PublicReplay {
  constructor(root, map, library, points, zone, locale) {
    this.root = root
    this.map = map
    this.library = library
    this.zone = zone
    this.locale = locale
    this.panel = root.querySelector("[data-public-replay-panel]")
    this.speed = 2
    this.follow = false
    this.timer = null
    this.day = 0
    this.index = 0
    const groups = new Map()
    const format = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    })
    for (const point of points) {
      const date = format.format(new Date(point[2] * 1000))
      if (!groups.has(date)) groups.set(date, [])
      groups.get(date).push(point)
    }
    this.days = [...groups].sort().map(([date, rows]) => ({
      date,
      points: rows.sort((a, b) => a[2] - b[2]),
    }))
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
  minute(point) {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: this.zone,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(point[2] * 1000))
    const value = (type) =>
      Number(parts.find((part) => part.type === type).value)
    return value("hour") * 60 + value("minute")
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
    const minute = this.minute(point)
    this.text(
      "replayTimeDisplay",
      `${String(Math.floor(minute / 60)).padStart(2, "0")}:${String(minute % 60).padStart(2, "0")}`,
    )
    this.text(
      "replayDayDisplay",
      new Intl.DateTimeFormat(this.locale, {
        timeZone: this.zone,
        dateStyle: "medium",
      }).format(new Date(point[2] * 1000)),
    )
    this.text("replayDayCount", `${this.day + 1} / ${this.days.length}`)
    const scrubber = this.target("replayScrubber")
    if (scrubber) scrubber.value = String(minute)
    const same = rows.filter((row) => this.minute(row) === minute)
    this.hidden("replayCycleControls", same.length < 2)
    this.text(
      "replayPointCounter",
      `${same.indexOf(point) + 1} / ${same.length}`,
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
      const rows = this.current()
      let nearest = 0
      for (let i = 1; i < rows.length; i++)
        if (
          Math.abs(this.minute(rows[i]) - Number(value)) <
          Math.abs(this.minute(rows[nearest]) - Number(value))
        )
          nearest = i
      this.index = nearest
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
      const rows = this.current(),
        next = this.index + (name === "replayCycleNext" ? 1 : -1)
      if (
        rows[next] &&
        this.minute(rows[next]) === this.minute(rows[this.index])
      )
        this.index = next
      this.draw()
    }
  }
  clear() {
    this.pause()
    this.marker?.remove()
    this.marker = null
    this.days = []
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
