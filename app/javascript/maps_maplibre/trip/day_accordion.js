import { translate } from "i18n"

export function applyDayColors(controller, dayKeys) {
  if (!controller.hasDaysAccordionTarget) return

  for (const dayKey of dayKeys) {
    const color = controller.dayRoutesLayer.getDayColor(dayKey)
    const dot = controller.daysAccordionTarget.querySelector(
      `[data-day-dot="${dayKey}"]`,
    )
    if (dot && color) {
      dot.style.backgroundColor = color
    }
  }
}

export function selectDayFromMap(controller, dayKey) {
  if (!controller.hasDaysAccordionTarget) return

  const target = controller.daysAccordionTarget.querySelector(
    `details[data-day-key="${dayKey}"]`,
  )
  if (!target) return

  openDay(controller, target, dayKey)
  target.scrollIntoView({ behavior: "smooth", block: "nearest" })
  controller.replayPanel?.syncToDay(dayKey)
}

export function toggleDay(controller, event) {
  event.preventDefault()

  const summary = event.currentTarget
  const details = summary.closest("details")
  const dayKey = summary.dataset.tripMaplibreDayKeyParam
  if (!details || !dayKey) return

  if (details.open) {
    details.removeAttribute("open")
    controller.selectedDay = null

    if (controller.dayRoutesLayer) {
      controller.dayRoutesLayer.selectAllDays()
      controller.fitFullBounds()
    }
  } else {
    openDay(controller, details, dayKey)
    controller.replayPanel?.syncToDay(dayKey)
  }
}

export function expandAllDays(controller) {
  if (!controller.hasDaysAccordionTarget) return

  const allDetails = dayDetails(controller)
  const allOpen = Array.from(allDetails).every((d) => d.hasAttribute("open"))

  for (const d of allDetails) {
    d.toggleAttribute("open", !allOpen)
  }
  if (controller.hasExpandAllBtnTarget) {
    controller.expandAllBtnTarget.textContent = allOpen
      ? translate("trip.show_all_days")
      : translate("trip.collapse_all_days")
  }

  controller.selectedDay = null

  if (controller.dayRoutesLayer) {
    controller.dayRoutesLayer.selectAllDays()
    controller.fitFullBounds()
  }
}

function dayDetails(controller) {
  return controller.daysAccordionTarget.querySelectorAll(
    "details[data-day-key]",
  )
}

function openDay(controller, details, dayKey) {
  for (const d of dayDetails(controller)) {
    if (d !== details) {
      d.removeAttribute("open")
    }
  }
  details.setAttribute("open", "")

  controller.selectedDay = dayKey

  if (controller.dayRoutesLayer) {
    controller.dayRoutesLayer.selectDay(dayKey)

    const dayBounds = controller.dayRoutesLayer.getDayBounds(dayKey)
    if (dayBounds) {
      controller.map.fitBounds(dayBounds, { padding: 50, maxZoom: 15 })
    }
  }
}
