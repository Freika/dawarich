function yearIn(date, timeZone) {
  return new Intl.DateTimeFormat("en", { timeZone, year: "numeric" }).format(
    new Date(date),
  )
}

export function groupVisitsByYear(visits, timeZone) {
  const groups = {}
  visits.forEach((visit) => {
    const year = yearIn(visit.date, timeZone)
    if (!groups[year]) groups[year] = []
    groups[year].push(visit)
  })
  return groups
}

export function createVisitResults({
  container,
  document,
  translate,
  timezone,
  search,
  flyTo,
  pushEvent,
}) {
  let generation = 0
  let controller = null
  let destroyed = false

  const node = (className, text, tag = "div") => {
    const child = document.createElement(tag)
    if (className) child.className = className
    if (text != null) child.textContent = text
    return child
  }

  function show(...children) {
    container.replaceChildren(...children)
    container.classList.remove("hidden")
  }

  function stamp(date, options) {
    return new Intl.DateTimeFormat(
      document.documentElement?.lang || undefined,
      {
        timeZone: timezone(),
        ...options,
      },
    ).format(new Date(date))
  }

  const short = (date) =>
    stamp(date, { month: "short", day: "numeric", year: "numeric" })

  function pick(location, visit) {
    if (destroyed) return
    const [lat, lon] = visit.coordinates || location.coordinates
    flyTo({ lat, lon, zoom: 18 })
    const details = visit.visit_details || {}
    pushEvent("visit:new", {
      name:
        location.place_name ||
        location.address ||
        translate("search.unnamed_location"),
      latitude: lat,
      longitude: lon,
      started_at: details.start_time || visit.date,
      ended_at: details.end_time || visit.date,
    })
  }

  function yearSection(location, index, year, yearVisits, visits) {
    const section = node("year-section")
    const toggle = node(
      "year-toggle p-3 hover:bg-base-300 cursor-pointer border-b flex justify-between items-center",
    )
    toggle.setAttribute("data-location-index", String(index))
    toggle.setAttribute("data-year", year)
    const arrow = node(
      "year-arrow text-base-content/40 transition-transform",
      "▶",
      "span",
    )
    const counts = node("flex items-center gap-2")
    counts.append(
      node(
        "text-xs text-primary",
        translate("selection.visits", { count: yearVisits.length }),
        "span",
      ),
      arrow,
    )
    toggle.append(node("text-sm font-medium", year, "span"), counts)
    const list = node("year-visits hidden")
    list.setAttribute("id", `year-${index}-${year}`)
    toggle.addEventListener("click", () => {
      const hidden = list.classList.toggle("hidden")
      arrow.style.transform = hidden ? "rotate(0deg)" : "rotate(90deg)"
    })
    for (const visit of yearVisits) {
      const item = node(
        "visit-item text-xs py-2 px-4 border-b hover:bg-base-300 cursor-pointer",
      )
      item.setAttribute("data-location-index", String(index))
      item.setAttribute("data-visit-index", String(visits.indexOf(visit)))
      const line = node("flex justify-between items-start")
      line.append(
        node(
          null,
          `📍 ${stamp(visit.date, { month: "short", day: "numeric", year: "numeric", hour: "2-digit", minute: "2-digit" })}`,
        ),
        node(
          "text-xs text-base-content/60",
          visit.duration_estimate || translate("common.not_available"),
        ),
      )
      item.append(line)
      item.addEventListener("click", () => pick(location, visit))
      list.append(item)
    }
    section.append(toggle, list)
    return section
  }

  function locationNode(location, index) {
    const visits = location.visits || []
    const sorted = [...visits].sort(
      (a, b) => new Date(a.date) - new Date(b.date),
    )
    const wrapper = node("location-result border-b")
    wrapper.setAttribute("data-location-index", String(index))
    const summary = node("p-4")
    summary.append(
      node(
        "font-medium text-sm",
        location.place_name ||
          location.address ||
          translate("map_info.location_coordinates", {
            latitude: location.coordinates?.[0]?.toFixed(4),
            longitude: location.coordinates?.[1]?.toFixed(4),
          }),
      ),
    )
    if (location.address && location.place_name !== location.address)
      summary.append(
        node("text-xs text-base-content/60 mt-1", location.address),
      )
    const meta = node("flex justify-between items-center mt-3")
    meta.append(
      node(
        "text-xs text-primary",
        translate("selection.visits", { count: location.total_visits }),
      ),
      node(
        "text-xs text-base-content/60",
        translate("search.first_last", {
          first: short(sorted[0].date),
          last: short(sorted[sorted.length - 1].date),
        }),
      ),
    )
    summary.append(meta)
    const years = node("border-t bg-base-200")
    for (const [year, yearVisits] of Object.entries(
      groupVisitsByYear(visits, timezone()),
    ))
      years.append(yearSection(location, index, year, yearVisits, visits))
    wrapper.append(summary, years)
    return wrapper
  }

  async function open(location) {
    if (destroyed) return
    generation++
    controller?.abort()
    controller = new AbortController()
    const current = generation
    flyTo({ lat: location.lat, lon: location.lon, zoom: 15 })
    const waiting = node("p-4 text-sm text-base-content/60")
    const heading = node("flex items-center gap-2 mb-2")
    heading.append(
      node("loading loading-spinner loading-sm", null, "span"),
      node("font-medium", translate("search.searching_for_visits"), "span"),
    )
    waiting.append(heading, node("text-xs", location.name))
    show(waiting)
    try {
      const data = await search.visits(location, { signal: controller.signal })
      if (destroyed || current !== generation) return
      const locations = (data?.locations || []).filter(
        (item) => (item.visits || []).length > 0,
      )
      if (locations.length === 0) {
        const empty = node("p-6 text-center text-base-content/60")
        empty.append(
          node("text-3xl mb-3", "📍"),
          node("text-sm font-medium", translate("visits.none_found")),
          node(
            "text-xs mt-1",
            translate("visits.none_found_for", { query: location.name }),
          ),
        )
        return show(empty)
      }
      const header = node("p-4 border-b bg-base-200")
      header.append(
        node(
          "text-sm font-medium",
          translate("search.locations_found", { count: data.total_locations }),
        ),
        node(
          "text-xs text-base-content/60 mt-1",
          translate("search.for_query", { query: location.name }),
        ),
      )
      show(header, ...locations.map(locationNode))
    } catch (error) {
      if (destroyed || current !== generation || error?.name === "AbortError")
        return
      show(
        node("p-3 text-sm text-error", translate("search.visits_load_failed")),
      )
    }
  }

  function clear() {
    generation++
    controller?.abort()
    container.replaceChildren()
    container.classList.add("hidden")
  }

  function destroy() {
    if (destroyed) return
    clear()
    destroyed = true
  }

  return { open, clear, destroy }
}
