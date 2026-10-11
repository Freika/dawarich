import { createRequestScope } from "../data/request_scope.js"
import { createFamilyOverlay } from "./overlay.js"

export function createMapFamilyLayer({
  map,
  reader,
  library,
  root,
  timers = globalThis,
  createOverlay = createFamilyOverlay,
}) {
  const requests = createRequestScope(timers)
  let overlay,
    overlayLocale,
    config,
    poll,
    destroyed = false
  const list = () => root?.querySelector("#native-family-members")
  const status = () => root?.querySelector("#native-family-status")
  const empty = () => root?.querySelector("[data-map-family-empty]")
  function clearView() {
    overlay?.clear()
    list()?.replaceChildren()
    if (list()) list().hidden = true
    if (status()) status().textContent = ""
    if (empty()) empty().hidden = !config?.familyEnabled
  }
  function stop() {
    if (poll !== undefined) timers.clearInterval(poll)
    poll = undefined
  }
  function clear(next) {
    if (next) config = next
    requests.reset()
    clearView()
    if (!config?.familyEnabled) {
      stop()
      overlay?.destroy()
      overlay = null
    }
  }
  function render(rows) {
    const container = list()
    if (!container) return
    const document = root.ownerDocument
    container.replaceChildren(
      ...rows.map((row) => {
        const button = document.createElement("button")
        button.setAttribute("type", "button")
        button.setAttribute(
          "class",
          "btn btn-ghost h-auto w-full justify-start text-left whitespace-normal [overflow-wrap:anywhere]",
        )
        button.setAttribute("data-family-member-id", String(row.user_id))
        const stamp = new Date(Number(row.timestamp) * 1000)
        const when = Number.isFinite(stamp.getTime())
          ? new Intl.DateTimeFormat(config.locale, {
              dateStyle: "medium",
              timeStyle: "short",
              timeZone: config.range?.timezone || "UTC",
            }).format(stamp)
          : ""
        button.textContent = `${row.name || row.email || ""} · ${when}`
        button.addEventListener("click", () => {
          if (destroyed || !config.familyEnabled || !container.isConnected)
            return
          map.flyTo({ center: [row.longitude, row.latitude], zoom: 15 })
          if (status())
            status().textContent =
              status().dataset.centered ||
              config.uiLabels?.["messages.centered_on_family_member"] ||
              ""
        })
        return button
      }),
    )
    container.hidden = rows.length === 0
    if (empty()) empty().hidden = rows.length > 0
  }
  async function update(next, { signal } = {}) {
    if (destroyed) return
    clear(next)
    if (!config.familyEnabled) return
    if (!overlay || overlayLocale !== config.locale) {
      overlay?.destroy()
      overlay = createOverlay({
        map,
        library,
        locale: config.locale,
        timers,
        colorMode: "id",
      })
      overlayLocale = config.locale
    }
    const operation = requests.begin(signal)
    try {
      const [latest, history] = await operation.wait(
        Promise.all([
          reader.read("family_locations", {}, { signal: operation.signal }),
          config.range?.startAt && config.range?.endAt
            ? reader.read(
                "family_history",
                { start_at: config.range.startAt, end_at: config.range.endAt },
                { signal: operation.signal },
              )
            : Promise.resolve({ data: { members: [] } }),
        ]),
      )
      operation.check()
      const rows = (latest.data.locations || []).filter(
        (row) =>
          Number.isFinite(row.longitude) &&
          Number.isFinite(row.latitude) &&
          Math.abs(row.longitude) <= 180 &&
          Math.abs(row.latitude) <= 90,
      )
      overlay.replace(rows, history.data.members || [])
      render(rows)
    } catch {
      if (operation.revision === requests.revision) clearView()
    } finally {
      operation.close()
    }
    if (!destroyed && config.familyEnabled && poll === undefined)
      poll = timers.setInterval(() => update(config), 30000)
  }
  return {
    update,
    clear,
    destroy() {
      if (destroyed) return
      destroyed = true
      requests.destroy()
      stop()
      clearView()
      overlay?.destroy()
      overlay = null
    },
  }
}
