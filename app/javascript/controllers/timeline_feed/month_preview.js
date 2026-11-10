import { firstDayOfWeek } from "i18n"
import { monthGridStart } from "maps_maplibre/utils/month_grid"

/**
 * Calendar month skeleton shown while the real month streams in.
 * Mixed into the controller; `this` is the controller.
 */
export const monthPreview = {
  // ---------- Calendar month skeleton ----------
  // Paints a "neutral" version of the target month immediately on click,
  // so users see the new month structure without waiting for the
  // turbo_stream round-trip. The stream then swaps this skeleton out for
  // the real heat-colored cells the moment the response arrives.
  previewMonth(event) {
    const link = event.currentTarget
    const targetMonth = link?.dataset?.targetMonth
    if (!targetMonth) return

    const calendar = this.element.querySelector(
      '[data-testid="timeline-calendar"]',
    )
    if (!calendar) return

    const grid = calendar.querySelector(
      ".grid.grid-cols-7.gap-0\\.5:last-child",
    )
    const title = calendar.querySelector('[data-testid="calendar-title"]')
    if (!grid || !title) return

    const [yearStr, monthStr] = targetMonth.split("-")
    const year = Number.parseInt(yearStr, 10)
    const monthIdx = Number.parseInt(monthStr, 10) - 1
    if (!Number.isFinite(year) || !Number.isFinite(monthIdx)) return

    // Force English locale to match the server-rendered title
    // (`strftime('%B %Y')`) — otherwise users on a non-English browser see
    // a brief "Январь 2025" → "January 2025" flicker as the turbo_stream
    // response replaces the skeleton.
    title.textContent = new Date(year, monthIdx, 1).toLocaleDateString("en", {
      month: "long",
      year: "numeric",
    })

    // 6×7 grid aligned to the first day of week — mirrors MonthSummary.
    const gridStart = monthGridStart(year, monthIdx, firstDayOfWeek())

    const cells = []
    for (let i = 0; i < 42; i += 1) {
      const d = new Date(gridStart)
      d.setDate(gridStart.getDate() + i)
      const inMonth = d.getMonth() === monthIdx
      const iso = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
      const selected = iso === this.selectedDate
      const classes = [
        "cal-cell",
        "heat-0",
        "cal-cell--dark-text",
        inMonth ? null : "out-of-month",
        selected ? "cal-cell--selected" : null,
      ]
        .filter(Boolean)
        .join(" ")
      cells.push(
        `<button type="button" class="${classes}" data-day="${iso}" data-action="click->timeline-feed#selectDay" data-testid="calendar-day" disabled><span class="cal-cell__day">${d.getDate()}</span></button>`,
      )
    }

    grid.innerHTML = cells.join("")
    calendar.classList.add("timeline-calendar--loading")
  },

  // ---------- Day navigation ----------
}
