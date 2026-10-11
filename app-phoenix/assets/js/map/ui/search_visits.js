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

  const node = (tag, text, className) => {
    const child = document.createElement(tag)
    if (text != null) child.textContent = text
    if (className) child.setAttribute("class", className)
    return child
  }

  function show(...children) {
    container.replaceChildren(...children)
    container.hidden = false
  }

  function stamp(date, options) {
    return new Intl.DateTimeFormat(undefined, {
      timeZone: timezone(),
      ...options,
    }).format(new Date(date))
  }

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

  function locationNode(location) {
    const visits = location.visits || []
    const wrapper = node("section", null, "border-b min-w-0")
    const name =
      location.place_name ||
      location.address ||
      translate("map_info.location_coordinates", {
        latitude: location.coordinates?.[0]?.toFixed(4),
        longitude: location.coordinates?.[1]?.toFixed(4),
      })
    wrapper.append(
      node("p", name, "font-medium text-sm [overflow-wrap:anywhere]"),
    )
    if (location.address && location.place_name !== location.address)
      wrapper.append(
        node("p", location.address, "text-xs [overflow-wrap:anywhere]"),
      )
    wrapper.append(
      node(
        "p",
        translate("selection.visits", { count: location.total_visits }),
        "text-xs text-primary",
      ),
    )
    for (const [year, yearVisits] of Object.entries(
      groupVisitsByYear(visits, timezone()),
    )) {
      const group = node("details", null, "border-t")
      group.append(node("summary", `${year} · ${yearVisits.length}`, "text-sm"))
      for (const visit of yearVisits) {
        const row = node(
          "button",
          `${stamp(visit.date, { dateStyle: "medium", timeStyle: "short" })} · ${visit.duration_estimate || translate("common.not_available")}`,
          "btn btn-ghost btn-xs w-full justify-between",
        )
        row.setAttribute("type", "button")
        row.setAttribute("data-visit-index", String(visits.indexOf(visit)))
        row.addEventListener("click", () => pick(location, visit))
        group.append(row)
      }
      wrapper.append(group)
    }
    return wrapper
  }

  async function open(location) {
    if (destroyed) return
    generation++
    controller?.abort()
    controller = new AbortController()
    const current = generation
    flyTo({ lat: location.lat, lon: location.lon, zoom: 15 })
    show(node("p", translate("search.searching_for_visits")))
    try {
      const data = await search.visits(location, { signal: controller.signal })
      if (destroyed || current !== generation) return
      const locations = (data?.locations || []).filter(
        (item) => (item.visits || []).length > 0,
      )
      if (locations.length === 0)
        return show(
          node("p", translate("visits.none_found")),
          node(
            "p",
            translate("visits.none_found_for", { query: location.name }),
          ),
        )
      show(
        node(
          "p",
          translate("search.locations_found", { count: data.total_locations }),
          "text-sm font-medium",
        ),
        ...locations.map(locationNode),
      )
    } catch (error) {
      if (destroyed || current !== generation || error?.name === "AbortError")
        return
      show(node("p", translate("search.visits_load_failed"), "text-error"))
    }
  }

  function clear() {
    generation++
    controller?.abort()
    container.replaceChildren()
    container.hidden = true
  }

  function destroy() {
    if (destroyed) return
    clear()
    destroyed = true
  }

  return { open, clear, destroy }
}
