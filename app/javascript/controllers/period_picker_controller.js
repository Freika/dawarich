import { Controller } from "@hotwired/stimulus"
import AirDatepicker from "air-datepicker"
import { firstDayOfWeek } from "i18n"

const pad = (number) => String(number).padStart(2, "0")
const iso = (date) =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
const atNoon = (day) => new Date(`${day}T12:00:00`)

// The one place the map's period is chosen: a button naming the period, with
// a calendar (Air Datepicker) behind it. The first click is the start of the
// period, the second its end; clicking away after one click takes that single
// day. The picker only says what was picked; the Timeline controller owns the
// period and applies it, and tells the picker back through
// `timeline-feed:date-navigated`.
export default class extends Controller {
  static targets = ["label", "popover", "calendar", "startTime", "endTime"]
  static values = { locale: String, url: String }

  connect() {
    // What the calendar shows about each day, by ISO date, and the months
    // already asked for.
    this.days = {}
    this.months = new Set()
    // The period's dates as the calendar last showed them.
    this.shown = []

    this.onNavigated = (event) => {
      const { startAt, endAt } = event.detail || {}
      if (!startAt || !endAt) return
      this.showPeriod(startAt, endAt)
      // The date fields are updated by a sibling listener of this event.
      queueMicrotask(() => this.syncCalendar())
    }
    // The path, not `contains`: a click on a day of the neighbouring month
    // makes the calendar redraw its cells, and the clicked one is detached by
    // the time the click reaches the document.
    this.onOutsideClick = (event) => {
      if (!event.composedPath().includes(this.popoverTarget)) this.close()
    }
    // Visits and notes change what a day looks like in the calendar.
    this.forget = () => {
      this.days = {}
      this.months.clear()
      if (this.picker) this.loadMonth(this.picker.viewDate)
    }
    document.addEventListener("timeline-feed:date-navigated", this.onNavigated)
    document.addEventListener("click", this.onOutsideClick)
    for (const name of ["visit:updated", "note:saved", "note:deleted"]) {
      document.addEventListener(name, this.forget)
    }

    const [start, end] = this.period()
    if (start && end) this.showPeriod(start, end)
  }

  disconnect() {
    document.removeEventListener(
      "timeline-feed:date-navigated",
      this.onNavigated,
    )
    document.removeEventListener("click", this.onOutsideClick)
    for (const name of ["visit:updated", "note:saved", "note:deleted"]) {
      document.removeEventListener(name, this.forget)
    }
    this.picker?.destroy()
    this.picker = null
  }

  // The period as the page holds it: two wall-clock "YYYY-MM-DDTHH:MM" values.
  period() {
    return ["start_at", "end_at"].map(
      (name) => this.element.querySelector(`input[name="${name}"]`)?.value,
    )
  }

  close() {
    this.popoverTarget.open = false
  }

  toggled() {
    if (this.popoverTarget.open) {
      this.buildCalendar()
      this.syncCalendar()
    } else if (this.pending) {
      // One click and away: that single day is the period.
      this.apply(this.pending, this.pending)
    }
  }

  // "Nov 5 – 7, 2026", or one date when the period is a single day. The
  // values are wall-clock strings, so only their dates are read.
  showPeriod(startAt, endAt) {
    const [from, to] = [startAt, endAt].map((value) =>
      atNoon(String(value).slice(0, 10)),
    )
    if (Number.isNaN(from.valueOf()) || Number.isNaN(to.valueOf())) return
    this.labelTarget.textContent = new Intl.DateTimeFormat(
      this.localeValue || undefined,
      { dateStyle: "medium" },
    ).formatRange(from, to)
  }

  buildCalendar() {
    if (this.picker) return
    this.picker = new AirDatepicker(this.calendarTarget, {
      inline: true,
      range: true,
      toggleSelected: false,
      locale: this.calendarLocale(),
      firstDay: firstDayOfWeek(),
      onRenderCell: ({ date, cellType }) =>
        cellType === "day" ? this.cellOptions(this.days[iso(date)]) : undefined,
      onChangeViewDate: ({ month, year }) =>
        this.loadMonth(new Date(year, month, 1)),
      onSelect: ({ date }) => this.picked([].concat(date || [])),
    })
    this.loadMonth(this.picker.viewDate)
  }

  // Month and weekday names in the interface language, from the browser.
  calendarLocale() {
    const names = (options, count, at) =>
      Array.from({ length: count }, (_, index) =>
        new Intl.DateTimeFormat(this.localeValue || undefined, options).format(
          at(index),
        ),
      )
    const weekday = (index) => new Date(2023, 0, 1 + index) // a Sunday
    const month = (index) => new Date(2023, index, 1)
    return {
      days: names({ weekday: "long" }, 7, weekday),
      daysShort: names({ weekday: "short" }, 7, weekday),
      daysMin: names({ weekday: "narrow" }, 7, weekday),
      months: names({ month: "long" }, 12, month),
      monthsShort: names({ month: "short" }, 12, month),
      today: "",
      clear: "",
      dateFormat: "yyyy-MM-dd",
      timeFormat: "HH:mm",
      firstDay: firstDayOfWeek(),
    }
  }

  // Heat of the day and a mark for a day with notes.
  cellOptions(day) {
    if (!day) return undefined
    const classes = [`heat-${day.heat || 0}`]
    if (day.noted) classes.push("-noted-")
    return { classes: classes.join(" "), disabled: day.disabled || undefined }
  }

  async loadMonth(viewDate) {
    const month = `${viewDate.getFullYear()}-${pad(viewDate.getMonth() + 1)}`
    if (this.months.has(month)) return
    this.months.add(month)
    try {
      const response = await fetch(`${this.urlValue}?month=${month}`, {
        headers: { Accept: "application/json" },
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      Object.assign(this.days, (await response.json()).days)
    } catch (error) {
      // The calendar still picks dates without its colours.
      this.months.delete(month)
      console.error("Failed to load the calendar month:", error)
      return
    }
    this.paintCells()
  }

  // The cells on screen were drawn before their month's data arrived.
  paintCells() {
    if (!this.picker) return
    for (const cell of this.calendarTarget.querySelectorAll(
      ".air-datepicker-cell.-day-",
    )) {
      const { year, month, date } = cell.dataset
      const options = this.cellOptions(
        this.days[`${year}-${pad(Number(month) + 1)}-${pad(date)}`],
      )
      if (!options) continue
      cell.classList.add(...options.classes.split(" "))
      cell.classList.toggle("-disabled-", Boolean(options.disabled))
    }
  }

  // The first click starts a new period, whatever was shown; the second
  // ends it. The library alone would take the first click as the end of a
  // one-day period, so the selection is restarted from the clicked day.
  picked(dates) {
    if (this.syncing || !dates.length) return
    if (this.pending) {
      this.apply(this.pending, dates.at(-1))
      this.close()
      return
    }
    const clicked =
      dates.find((date) => !this.shown.includes(iso(date))) || dates[0]
    this.select([clicked])
    this.pending = clicked
  }

  // Put dates into the calendar without it reporting them as a pick.
  select(dates) {
    this.syncing = true
    this.picker.clear({ silent: true })
    this.picker.selectDate(dates, { silent: true })
    this.syncing = false
  }

  // Whole days unless the time fields say otherwise.
  apply(from, to) {
    this.pending = null
    const [first, last] = [iso(from), iso(to)].sort()
    const start = this.startTimeTarget.value || "00:00"
    const end = this.endTimeTarget.value || "23:59"
    document.dispatchEvent(
      new CustomEvent("period-picker:range", {
        detail: {
          startAt: `${first}T${start}:00`,
          endAt: `${last}T${end}:59`,
        },
      }),
    )
  }

  timeChanged() {
    const [start, end] = this.period()
    if (start && end)
      this.apply(atNoon(start.slice(0, 10)), atNoon(end.slice(0, 10)))
  }

  // Show the page's period in the calendar and the time fields.
  syncCalendar() {
    const [start, end] = this.period()
    if (!start || !end) return
    this.startTimeTarget.value = start.slice(11, 16)
    this.endTimeTarget.value = end.slice(11, 16)
    if (!this.picker) return

    this.pending = null
    this.shown = [start.slice(0, 10), end.slice(0, 10)]
    // Both ends even for a single day: one date alone would read as a period
    // being picked, and the calendar would preview a range on hover.
    this.select(this.shown.map(atNoon))
    this.picker.setViewDate(atNoon(end.slice(0, 10)))
  }
}
