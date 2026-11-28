import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "scroller",
    "grid",
    "tooltip",
    "tooltipDate",
    "tooltipDetail",
    "modeButton",
    "countryButton",
  ]
  static values = { targetDate: String, noData: String }

  connect() {
    this.centerOnTargetDate()
  }

  centerOnTargetDate() {
    if (!this.targetDateValue || !this.hasScrollerTarget) return

    const cell = this.gridTarget.querySelector(
      `[data-date="${this.targetDateValue}"]`,
    )
    if (!cell) return

    const scroller = this.scrollerTarget
    const offset =
      cell.getBoundingClientRect().left - scroller.getBoundingClientRect().left
    scroller.scrollLeft += offset - scroller.clientWidth / 2
  }

  show(event) {
    const cell = event.target.closest("[data-date]")
    if (!cell) return this.hide()

    const detail = [cell.dataset.country, cell.dataset.distance]
      .filter(Boolean)
      .join(" · ")
    this.tooltipDateTarget.textContent = cell.dataset.label
    this.tooltipDetailTarget.textContent = detail || this.noDataValue

    const tooltip = this.tooltipTarget
    const box = tooltip.parentElement.getBoundingClientRect()
    const rect = cell.getBoundingClientRect()
    tooltip.classList.remove("hidden")

    let left = rect.left - box.left + rect.width / 2 - tooltip.offsetWidth / 2
    left = Math.max(0, Math.min(left, box.width - tooltip.offsetWidth))
    tooltip.style.left = `${left}px`
    tooltip.style.top = `${rect.top - box.top - tooltip.offsetHeight - 6}px`
  }

  hide() {
    this.tooltipTarget.classList.add("hidden")
  }

  setMode(event) {
    const mode = event.currentTarget.dataset.mode
    this.gridTarget.dataset.mode = mode
    this.modeButtonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.mode === mode))
    })
  }

  focusCountry(event) {
    const country = event.currentTarget.dataset.country
    const focused = this.gridTarget.dataset.focus === country ? null : country

    if (focused) this.gridTarget.dataset.focus = focused
    else delete this.gridTarget.dataset.focus

    this.gridTarget.querySelectorAll("[data-date]").forEach((cell) => {
      cell.classList.toggle(
        "is-focused",
        Boolean(focused) && cell.dataset.country === focused,
      )
    })
    this.countryButtonTargets.forEach((button) => {
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.country === focused),
      )
    })
  }
}
