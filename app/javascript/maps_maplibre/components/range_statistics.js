import { formatNumber, translate } from "i18n"

export class RangeStatistics {
  constructor(element, api, unit = "km") {
    this.element = element
    this.api = api
    this.unit = unit
    this.generation = 0
  }

  async load(start_at, end_at) {
    clearTimeout(this.refreshTimer)
    this.range = [start_at, end_at]
    this.abort?.abort()
    const generation = ++this.generation
    this.abort = new AbortController()
    this.data = null
    this.element.textContent = translate("common.loading")
    this.element.setAttribute("aria-busy", "true")
    try {
      const data = await this.api.fetchRangeStatistics({
        start_at,
        end_at,
        signal: this.abort.signal,
      })
      if (generation !== this.generation) return
      this.data = data
      this.render()
    } catch (error) {
      if (generation !== this.generation) return
      this.element.textContent = translate("range_statistics.unavailable")
    } finally {
      if (generation === this.generation)
        this.element.setAttribute("aria-busy", "false")
    }
  }

  refresh() {
    if (!this.range) return
    clearTimeout(this.refreshTimer)
    this.refreshTimer = setTimeout(() => this.load(...this.range), 300)
  }

  setUnit(unit) {
    this.unit = unit
    this.render()
  }

  render() {
    if (!this.data) return
    // Keep conversions aligned with DISTANCE_UNITS (01_constants.rb).
    const divisor = this.unit === "mi" ? 1609.34 : 1000
    const distance =
      Math.round((this.data.distance_meters / divisor) * 100) / 100
    this.element.textContent = translate("range_statistics.summary", {
      count: this.data.points,
      points: formatNumber(this.data.points),
      distance: formatNumber(distance),
      unit: this.unit,
    })
  }

  destroy() {
    clearTimeout(this.refreshTimer)
    this.generation++
    this.abort?.abort()
  }
}
