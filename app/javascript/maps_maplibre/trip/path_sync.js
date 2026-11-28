export function observePendingPath(controller) {
  // Recover path updates broadcast before the stream subscribes or reconnects.
  const sources = document.querySelectorAll("turbo-cable-stream-source")
  const observer = new MutationObserver((mutations) => {
    if (mutations.some(({ target }) => target.hasAttribute("connected"))) {
      syncPendingPath(controller)
    }
  })
  sources.forEach((source) => {
    observer.observe(source, {
      attributes: true,
      attributeFilter: ["connected"],
    })
  })
  if ([...sources].some((source) => source.hasAttribute("connected"))) {
    syncPendingPath(controller)
  }
  return observer
}

export async function syncPendingPath(controller) {
  if (!controller.hasPathPendingTarget) return
  // A request made mid-fetch may follow a newer path save, so rerun once.
  if (controller.syncingPath) {
    controller.pathSyncQueued = true
    return
  }

  controller.syncingPath = true
  try {
    const response = await fetch(window.location.href, {
      headers: { Accept: "text/html" },
      credentials: "same-origin",
    })
    if (!response.ok)
      throw new Error(`Trip path sync failed: ${response.status}`)

    const latest = new DOMParser().parseFromString(
      await response.text(),
      "text/html",
    )
    if (
      controller.element.isConnected &&
      controller.hasPathPendingTarget &&
      latest.querySelector('[data-trip-maplibre-target="map"]')
    ) {
      Turbo.visit(window.location.href, { action: "replace" })
    }
  } catch (error) {
    console.warn("Could not synchronize trip path", error)
  } finally {
    controller.syncingPath = false
    if (controller.pathSyncQueued) {
      controller.pathSyncQueued = false
      syncPendingPath(controller)
    }
  }
}
