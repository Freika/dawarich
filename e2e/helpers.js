import { expect } from "@playwright/test"

export async function blockOutboundAndStubBasemap(page) {
  await page.route("**/*", async (route) => {
    const url = new URL(route.request().url())
    if (url.pathname.startsWith("/e2e/basemap/")) {
      await route.fulfill({
        status: 204,
        contentType: "application/vnd.mapbox-vector-tile",
        body: "",
      })
      return
    }
    if (["127.0.0.1", "localhost"].includes(url.hostname)) {
      await route.continue()
      return
    }
    await route.abort("blockedbyclient")
  })
}

export async function waitForMapController(page) {
  await expect
    .poll(
      () =>
        page.evaluate(() => {
          const element = document.querySelector("#maps-maplibre-container")
          const controller =
            window.Stimulus?.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
          return Boolean(
            controller?.map &&
              controller?.layerManager?.getLayer("points-mvt") &&
              controller.map.getSource("points-mvt-source"),
          )
        }),
      { timeout: 60_000 },
    )
    .toBe(true)
}

export async function controllerState(page) {
  return page.evaluate(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    return {
      sourceIds: Object.keys(controller.map.getStyle().sources),
      layerIds: controller.map.getStyle().layers.map((layer) => layer.id),
      settings: controller.settings,
    }
  })
}
