export const InsightsCalendar = {
  mounted() {
    const find = (selector) => this.el.querySelector(selector)
    const scroller = find("[data-native-calendar-scroller]")
    const target = this.el.dataset.nativeTargetDate
    const cell = target && find(`[data-date="${target}"]`)
    if (cell && scroller && target !== this.calendarTarget) {
      scroller.scrollLeft += cell.getBoundingClientRect().left - scroller.getBoundingClientRect().left - scroller.clientWidth / 2
    }
    this.calendarTarget = target
    const tooltip = find("[data-native-calendar-tooltip]")
    this.calendarHide = () => tooltip.classList.add("hidden")
    this.calendarShow = (event) => {
      const cell = event.target.closest("[data-date]")
      if (!cell) return this.calendarHide()
      find("[data-native-tooltip-date]").textContent = cell.dataset.label
      find("[data-native-tooltip-detail]").textContent = [cell.dataset.country, cell.dataset.distance].filter(Boolean).join(" · ") || this.el.dataset.nativeNoData
      tooltip.classList.remove("hidden")
      const box = tooltip.parentElement.getBoundingClientRect()
      const rect = cell.getBoundingClientRect()
      tooltip.style.left = `${Math.max(0, Math.min(rect.left - box.left + rect.width / 2 - tooltip.offsetWidth / 2, box.width - tooltip.offsetWidth))}px`
      tooltip.style.top = `${rect.top - box.top - tooltip.offsetHeight - 6}px`
    }
    this.el.addEventListener("mouseover", this.calendarShow)
    this.el.addEventListener("mouseleave", this.calendarHide)
  },
  updated() {
    InsightsCalendar.destroyed.call(this)
    InsightsCalendar.mounted.call(this)
  },
  destroyed() {
    this.el.removeEventListener("mouseover", this.calendarShow)
    this.el.removeEventListener("mouseleave", this.calendarHide)
    this.calendarShow = this.calendarHide = null
  },
}

export const InsightsRace = {
  mounted() {
    const find = (selector) => this.el.querySelector(selector)
    const svg = find("[data-native-race-svg]")
    const hit = find("[data-native-race-hit]")
    const hover = find("[data-native-race-hover]")
    const line = find("[data-native-race-hover-line]")
    const tooltip = find("[data-native-race-tooltip]")
    const year = Number(this.el.dataset.nativeYear)
    const current = JSON.parse(this.el.dataset.nativeCurrent)
    const previous = JSON.parse(this.el.dataset.nativePrevious)
    const days = new Date(Date.UTC(year, 1, 29)).getUTCMonth() === 1 ? 366 : 365
    const locale = this.el.ownerDocument.documentElement.lang || undefined
    const dates = new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", timeZone: "UTC" })
    const numbers = new Intl.NumberFormat(locale, { maximumFractionDigits: 0 })
    const distance = (value) => `${numbers.format(value)} ${this.el.dataset.nativeUnit}`
    const scroller = svg.parentElement
    if (scroller.scrollWidth > scroller.clientWidth) scroller.scrollLeft = current.length / days * scroller.scrollWidth - scroller.clientWidth / 2
    this.raceShow = (event) => {
      const point = svg.createSVGPoint()
      point.x = event.clientX
      point.y = event.clientY
      const local = point.matrixTransform(svg.getScreenCTM().inverse())
      const index = Math.max(0, Math.min(days - 1, Math.round((local.x - 46) / 662 * (days - 1))))
      const x = 46 + index / (days - 1) * 662
      line.setAttribute("x1", x)
      line.setAttribute("x2", x)
      hover.setAttribute("visibility", "visible")
      find("[data-native-tooltip-date]").textContent = dates.format(new Date(Date.UTC(year, 0, index + 1)))
      find("[data-native-tooltip-current]").textContent = `${year}: ${current[index] == null ? "—" : distance(current[index])}`
      find("[data-native-tooltip-previous]").textContent = previous.length ? `${year - 1}: ${distance(previous[Math.min(index, previous.length - 1)])}` : ""
      tooltip.classList.remove("hidden")
      const box = tooltip.parentElement.getBoundingClientRect()
      let left = event.clientX - box.left + 12
      if (left + tooltip.offsetWidth > box.width) left = event.clientX - box.left - tooltip.offsetWidth - 12
      tooltip.style.left = `${Math.max(0, left)}px`
      tooltip.style.top = `${Math.max(0, event.clientY - box.top - tooltip.offsetHeight - 8)}px`
    }
    this.raceHide = () => {
      hover.setAttribute("visibility", "hidden")
      tooltip.classList.add("hidden")
    }
    this.raceHit = hit
    hit.addEventListener("mousemove", this.raceShow)
    hit.addEventListener("mouseleave", this.raceHide)
  },
  updated() {
    InsightsRace.destroyed.call(this)
    InsightsRace.mounted.call(this)
  },
  destroyed() {
    this.raceHit.removeEventListener("mousemove", this.raceShow)
    this.raceHit.removeEventListener("mouseleave", this.raceHide)
    this.raceHit = this.raceShow = this.raceHide = null
  },
}
