export function createEnrichmentResults({
  root,
  reader,
  map,
  library,
  timers = globalThis,
  pushEvent,
  confirm = (message) => globalThis.confirm(message),
  urls = globalThis.URL,
  onSubmitted,
}) {
  let host,
    list,
    all,
    submit,
    status,
    labels = {}
  function bind() {
    const next = root?.querySelector("[data-enrichment-results]")
    if (next === host) return
    all?.removeEventListener("change", selectAll)
    submit?.removeEventListener("click", enrich)
    host = next
    list = host?.querySelector("[data-enrichment-list]")
    all = host?.querySelector("[data-enrichment-all]")
    submit = host?.querySelector("[data-enrichment-submit]")
    status = host?.querySelector("[data-enrichment-status]")
    labels = JSON.parse(host?.dataset.labels ?? "{}")
    all?.addEventListener("change", selectAll)
    submit?.addEventListener("click", enrich)
  }
  const document = root?.ownerDocument
  let generation = 0,
    destroyed = false,
    busy = false,
    deadline = null,
    activeAttempt = null,
    popup = null
  let rows = [],
    checks = []
  const thumbnails = new Set(),
    objectURLs = new Set(),
    popupReads = new Set(),
    popupURLs = new Set()
  const translate = (key, bindings = {}) =>
    Object.entries(bindings).reduce(
      (text, [name, value]) => text.replaceAll(`{${name}}`, String(value)),
      (typeof labels[key] === "object"
        ? labels[key][bindings.count === 1 ? "one" : "other"]
        : labels[key]) ?? key,
    )
  const selected = () => rows.filter((_row, index) => checks[index]?.checked)
  function update() {
    if (!submit) return
    submit.disabled = busy || selected().length === 0
    submit.textContent = translate("enrich_photos", {
      count: selected().length,
    })
    all.checked = rows.length > 0 && selected().length === rows.length
    all.disabled = busy
    for (const check of checks) check.disabled = busy
  }
  function closePopup() {
    for (const controller of popupReads) controller.abort()
    popupReads.clear()
    for (const url of popupURLs) urls.revokeObjectURL(url)
    popupURLs.clear()
    popup?.off?.("close", closePopup)
    popup?.remove()
    popup = null
  }
  function clear() {
    generation++
    activeAttempt = null
    busy = false
    timers.clearTimeout(deadline)
    deadline = null
    closePopup()
    for (const controller of thumbnails) controller.abort()
    thumbnails.clear()
    for (const url of objectURLs) urls.revokeObjectURL(url)
    objectURLs.clear()
    rows = []
    checks = []
    list?.replaceChildren()
    if (status) status.textContent = ""
    update()
  }
  function thumbnail(image, row, current, popupImage = false) {
    if (!reader) return
    const controller = new AbortController()
    const controllers = popupImage ? popupReads : thumbnails
    const ownedURLs = popupImage ? popupURLs : objectURLs
    controllers.add(controller)
    reader
      .read(
        "thumbnail",
        { id: row.immich_asset_id, source: "immich" },
        { signal: controller.signal },
      )
      .then(({ data }) => {
        if (destroyed || current !== generation || controller.signal.aborted)
          return
        const url = urls.createObjectURL(data)
        ownedURLs.add(url)
        image.src = url
      })
      .catch(() => {
        image.hidden = true
      })
      .finally(() => controllers.delete(controller))
  }
  function showPopup(id) {
    closePopup()
    const row = rows.find((row) => row.immich_asset_id === id)
    if (!row || !library?.Popup || destroyed) return
    const content = document.createElement("div"),
      image = document.createElement("img"),
      title = document.createElement("p")
    content.className = "max-w-64 [overflow-wrap:anywhere]"
    title.textContent = row.filename ?? ""
    image.alt = row.filename ?? ""
    image.className = "max-w-full max-h-48"
    content.append(image, title)
    thumbnail(image, row, generation, true)
    popup = new library.Popup()
      .setLngLat([row.longitude, row.latitude])
      .setDOMContent(content)
      .addTo(map)
    popup.on?.("close", closePopup)
  }
  function replace(next) {
    bind()
    clear()
    if (destroyed || !list) return
    rows = next
    checks = rows.map((row) => {
      const item = document.createElement("label"),
        check = document.createElement("input"),
        image = document.createElement("img"),
        title = document.createElement("span")
      item.className = "flex flex-wrap items-center gap-2 min-w-0 rounded p-2"
      check.type = "checkbox"
      check.checked = true
      check.className = "checkbox checkbox-xs"
      check.setAttribute("aria-label", row.filename ?? row.immich_asset_id)
      check.addEventListener("change", update)
      image.alt = ""
      image.className = "w-10 h-10 object-cover rounded"
      title.textContent = row.filename ?? row.immich_asset_id
      title.className = "min-w-0 flex-1 [overflow-wrap:anywhere]"
      item.append(check, image, title)
      item.title = `${row.photo_timestamp ?? ""} (${row.time_delta_seconds ?? 0}s)`
      item.addEventListener("mouseenter", () => showPopup(row.immich_asset_id))
      item.addEventListener("mouseleave", closePopup)
      list.appendChild(item)
      thumbnail(image, row, generation)
      return check
    })
    update()
  }
  const selectAll = () => {
    for (const check of checks) check.checked = all.checked
    update()
  }
  const enrich = () => {
    const assets = selected().map(
      ({ immich_asset_id, latitude, longitude }) => ({
        immich_asset_id,
        latitude,
        longitude,
      }),
    )
    if (
      destroyed ||
      busy ||
      !assets.length ||
      !confirm(translate("confirm_enrich", { count: assets.length }))
    )
      return
    busy = true
    const current = generation
    const attempt = { settled: false }
    activeAttempt = attempt
    update()
    status.textContent = translate("enriching", { count: assets.length })
    const settle = (reply) => {
      if (
        destroyed ||
        current !== generation ||
        attempt.settled ||
        activeAttempt !== attempt
      )
        return
      attempt.settled = true
      activeAttempt = null
      timers.clearTimeout(deadline)
      deadline = null
      busy = false
      const result = reply?.result
      const accepted = reply?.ok && !result?.error
      if (accepted) {
        clear()
        onSubmitted?.()
      }
      status.textContent = accepted
        ? translate(
            result?.pending > 0
              ? "pending_enrichment"
              : result?.failed > 0
                ? "partially_enriched"
                : "enriched",
            {
              count: result?.pending || result?.enriched || 0,
              enriched: result?.enriched || 0,
              failed: result?.failed || 0,
            },
          )
        : translate("failed")
      update()
    }
    deadline = timers.setTimeout(() => settle({ error: "timeout" }), 60000)
    try {
      pushEvent("enrichment:enrich", { assets }, settle)
    } catch {
      settle({ error: "unavailable" })
    }
  }
  bind()
  return {
    replace,
    clear,
    showPopup,
    closePopup,
    destroy() {
      destroyed = true
      clear()
      all?.removeEventListener("change", selectAll)
      submit?.removeEventListener("click", enrich)
    },
  }
}
