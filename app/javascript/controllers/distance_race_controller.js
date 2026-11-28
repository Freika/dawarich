import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "svg",
    "hover",
    "hoverLine",
    "tooltip",
    "tooltipDate",
    "tooltipCurrent",
    "tooltipPrevious",
  ]
  static values = {
    current: Array,
    previous: Array,
    year: Number,
    unit: String,
    left: Number,
    right: Number,
  }

  connect() {
    this.dateFormat = new Intl.DateTimeFormat(
      document.documentElement.lang || undefined,
      {
        day: "numeric",
        month: "short",
      },
    )
    this.numberFormat = new Intl.NumberFormat(
      document.documentElement.lang || undefined,
      {
        maximumFractionDigits: 0,
      },
    )
    this.scrollToToday()
  }

  scrollToToday() {
    const scroller = this.svgTarget.parentElement
    if (scroller.scrollWidth <= scroller.clientWidth) return

    const share = this.currentValue.length / this.daysInYear()
    scroller.scrollLeft =
      share * scroller.scrollWidth - scroller.clientWidth / 2
  }

  show(event) {
    const point = this.svgTarget.createSVGPoint()
    point.x = event.clientX
    point.y = event.clientY
    const local = point.matrixTransform(this.svgTarget.getScreenCTM().inverse())

    const days = this.daysInYear()
    const ratio =
      (local.x - this.leftValue) / (this.rightValue - this.leftValue)
    const index = Math.max(
      0,
      Math.min(days - 1, Math.round(ratio * (days - 1))),
    )
    const x =
      this.leftValue + (index / (days - 1)) * (this.rightValue - this.leftValue)

    this.hoverLineTarget.setAttribute("x1", x)
    this.hoverLineTarget.setAttribute("x2", x)
    this.hoverTarget.setAttribute("visibility", "visible")

    const current = this.currentValue[index]
    const previous =
      this.previousValue[Math.min(index, this.previousValue.length - 1)]
    const date = new Date(Date.UTC(this.yearValue, 0, 1 + index))

    this.tooltipDateTarget.textContent = this.dateFormat.format(date)
    this.tooltipCurrentTarget.textContent = `${this.yearValue}: ${current == null ? "—" : this.distance(current)}`
    this.tooltipPreviousTarget.textContent = this.previousValue.length
      ? `${this.yearValue - 1}: ${this.distance(previous)}`
      : ""

    this.placeTooltip(event)
  }

  hide() {
    this.hoverTarget.setAttribute("visibility", "hidden")
    this.tooltipTarget.classList.add("hidden")
  }

  placeTooltip(event) {
    const tooltip = this.tooltipTarget
    const box = tooltip.parentElement.getBoundingClientRect()
    tooltip.classList.remove("hidden")

    let left = event.clientX - box.left + 12
    if (left + tooltip.offsetWidth > box.width)
      left = event.clientX - box.left - tooltip.offsetWidth - 12
    tooltip.style.left = `${Math.max(0, left)}px`
    tooltip.style.top = `${Math.max(0, event.clientY - box.top - tooltip.offsetHeight - 8)}px`
  }

  distance(value) {
    return `${this.numberFormat.format(value)} ${this.unitValue}`
  }

  daysInYear() {
    const year = this.yearValue
    return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0 ? 366 : 365
  }
}
