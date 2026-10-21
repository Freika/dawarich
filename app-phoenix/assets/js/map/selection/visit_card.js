const ICONS = {
  date: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />',
  time: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />',
  duration:
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />',
  delete:
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />',
  confirm:
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />',
  merge:
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />',
  selected:
    '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />',
  pin: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />',
}

export function createVisitCards({ document, translate }) {
  const node = (tag, className, text) => {
    const element = document.createElement(tag)
    if (className) element.className = className
    if (text != null) element.textContent = text
    return element
  }

  const icon = (name, className) => {
    const svg = node("span")
    svg.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="${className}" fill="none" viewBox="0 0 24 24" stroke="currentColor">${ICONS[name]}</svg>`
    return svg.firstChild ?? svg
  }

  const labelled = (name, className, text) => {
    const element = node("button", className)
    element.append(icon(name, "h-3 w-3"), ` ${text} `)
    return element
  }

  function row(name, text) {
    const line = node("div", "flex items-center gap-1.5")
    line.append(
      icon(name, "h-3.5 w-3.5 flex-shrink-0"),
      node("span", "truncate", text),
    )
    return line
  }

  function card(visit, { selected, onSelect, onConfirm, onDelete }) {
    const suggested = visit.status === "suggested"
    const confirmed = visit.status === "confirmed"
    const declined = visit.status === "declined"
    const locale = document.documentElement?.lang || undefined
    const start = new Date(visit.started_at)
    const end = new Date(visit.ended_at)
    const clock = { hour: "2-digit", minute: "2-digit" }
    const hours = Math.floor(visit.duration / 60)
    const minutes = visit.duration % 60
    const element = node(
      "div",
      [
        "visit-card card",
        declined ? "bg-base-200 opacity-60" : "bg-base-100",
        suggested ? "border-dashed" : "",
        selected ? "ring-2 ring-primary" : "",
        "border-2 border-base-content/20 mb-2 hover:shadow-md transition-all relative",
      ].join(" "),
    )
    element.setAttribute("data-visit-id", String(visit.id))
    element.setAttribute("data-visit-status", visit.status)

    const toggle = node(
      "div",
      `visit-checkbox absolute top-3 right-3 z-10 ${selected ? "" : "hidden"}`,
    )
    const box = node("input", "checkbox checkbox-primary checkbox-sm")
    box.setAttribute("type", "checkbox")
    box.setAttribute("data-visit-select", String(visit.id))
    box.checked = selected
    box.addEventListener("change", () => onSelect(box.checked))
    toggle.append(box)
    element.addEventListener("mouseenter", () =>
      toggle.classList.remove("hidden"),
    )
    element.addEventListener("mouseleave", () => {
      if (!box.checked) toggle.classList.add("hidden")
    })

    const body = node("div", "card-body p-3")
    const address = visit.place?.address
    body.append(
      node(
        "h3",
        `card-title text-sm font-semibold ${address ? "" : "mb-2"}`,
        visit.name || visit.place?.name || translate("visits.unnamed"),
      ),
    )
    if (address) {
      const line = node(
        "p",
        "text-xs text-base-content/70 mb-2 [overflow-wrap:anywhere]",
        address,
      )
      line.setAttribute("data-visit-address", "")
      body.append(line)
    }
    const details = node("div", "text-xs text-base-content/70 space-y-1")
    details.append(
      row(
        "date",
        start.toLocaleDateString(locale, {
          month: "short",
          day: "numeric",
          year: "numeric",
        }),
      ),
      row(
        "time",
        `${start.toLocaleTimeString(locale, clock)} - ${end.toLocaleTimeString(locale, clock)}`,
      ),
      row(
        "duration",
        hours > 0
          ? translate("map_info.duration_hours_minutes", { hours, minutes })
          : translate("map_info.duration_minutes", { minutes }),
      ),
    )
    body.append(details)
    if (suggested) {
      const actions = node("div", "card-actions justify-end mt-3 gap-1.5")
      const remove = labelled(
        "delete",
        "btn btn-xs btn-outline btn-error",
        translate("common.delete"),
      )
      remove.setAttribute("data-visit-delete", String(visit.id))
      remove.addEventListener("click", onDelete)
      const accept = labelled(
        "confirm",
        "btn btn-xs btn-primary",
        translate("common.confirm"),
      )
      accept.setAttribute("data-visit-confirm", String(visit.id))
      accept.addEventListener("click", onConfirm)
      actions.append(remove, accept)
      body.append(actions)
    }
    if (confirmed || declined) {
      const badge = node("div", "mt-2")
      badge.append(
        node(
          "span",
          `badge badge-xs ${confirmed ? "badge-success" : "badge-error"}`,
          translate(`visit_statuses.${visit.status}`),
        ),
      )
      body.append(badge)
    }
    element.append(toggle, body)
    return element
  }

  function list(count, cards) {
    const wrapper = node("div", "selected-visits-list")
    const header = node(
      "div",
      "flex items-center gap-2 mb-3 pb-2 border-b border-base-300",
    )
    header.append(
      icon("pin", "h-5 w-5 text-primary"),
      node(
        "h3",
        "text-sm font-bold",
        translate("selection.visits_in_area", { count }),
      ),
    )
    wrapper.append(header, ...cards)
    return wrapper
  }

  function bulk(count, { merge, confirm, remove, disabled }) {
    const wrapper = node("div", "bulk-actions-inline mb-2")
    const box = node(
      "div",
      "bg-primary/10 border-2 border-primary border-dashed rounded-lg p-3",
    )
    const title = node(
      "div",
      "text-xs font-semibold mb-2 text-primary flex items-center gap-2",
    )
    title.append(
      icon("selected", "h-4 w-4"),
      node("span", null, translate("visits.selected", { count })),
    )
    const grid = node("div", "grid grid-cols-3 gap-1.5")
    for (const [name, className, text, attribute, onClick] of [
      [
        "merge",
        "btn btn-xs btn-outline normal-case",
        translate("visits.merge"),
        "data-bulk-merge",
        merge,
      ],
      [
        "confirm",
        "btn btn-xs btn-primary normal-case",
        translate("common.confirm"),
        "data-bulk-confirm",
        confirm,
      ],
      [
        "delete",
        "btn btn-xs btn-outline btn-error normal-case",
        translate("common.delete"),
        "data-bulk-delete",
        remove,
      ],
    ]) {
      const button = labelled(name, className, text)
      button.setAttribute(attribute, "")
      button.disabled = disabled
      button.addEventListener("click", onClick)
      grid.append(button)
    }
    box.append(title, grid)
    wrapper.append(box)
    return wrapper
  }

  return { card, list, bulk }
}
