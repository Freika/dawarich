import { expect, test } from "@playwright/test"

const LOCATION = [13.4, 52.5]

async function addMergedPoint(page) {
  await page.route("**/api/v1/points/900001", (route) =>
    route.fulfill({
      json: {
        id: 900001,
        longitude: String(LOCATION[0]),
        latitude: String(LOCATION[1]),
        timestamp: 1_700_000_000,
      },
    }),
  )
  await page.route("**/points/900001/address", (route) =>
    route.fulfill({
      contentType: "text/html",
      body: '<turbo-frame id="point-address-900001">Berlin</turbo-frame>',
    }),
  )
  await page.goto("/map/v2")
  await page.waitForFunction(() => {
    const controller = window.Stimulus?.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    return controller?.map?.loaded() && controller?.map?.getLayer("points-mvt")
  })

  await page.evaluate((coordinates) => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    const map = controller.map
    map.jumpTo({ center: coordinates, zoom: 16 })
    map.removeLayer("points-mvt")
    map.addSource("issue-3719-points", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: { type: "Point", coordinates },
            properties: {
              id: 900001,
              count: 2,
              timestamp: 0,
              longitude: "0",
              latitude: "0",
            },
          },
        ],
      },
    })
    map.addLayer({
      id: "points-mvt",
      type: "circle",
      source: "issue-3719-points",
      paint: { "circle-radius": 9, "circle-color": "#3b82f6" },
    })
  }, LOCATION)
  await page.waitForFunction((coordinates) => {
    const map = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    ).map
    return (
      map.queryRenderedFeatures(map.project(coordinates), {
        layers: ["points-mvt"],
      }).length > 0
    )
  }, LOCATION)
}

async function markerPosition(page) {
  return page.evaluate((coordinates) => {
    const map = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    ).map
    const projected = map.project(coordinates)
    const rect = map.getCanvas().getBoundingClientRect()
    return { x: rect.left + projected.x, y: rect.top + projected.y }
  }, LOCATION)
}

test("a merged point marker opens a selectable point instead of zooming", async ({
  page,
}) => {
  await addMergedPoint(page)
  const position = await markerPosition(page)
  await page.mouse.move(position.x, position.y)
  const cursor = await page
    .locator(".maplibregl-canvas")
    .evaluate((canvas) => canvas.style.cursor)
  await page.mouse.click(position.x, position.y)

  const info = page.locator('[data-maps--maplibre-target="infoDisplay"]')
  await expect(info).toBeVisible()
  expect(cursor).toBe("pointer")
  await expect(info.getByRole("button", { name: "Delete" })).toBeVisible()
  await expect(info).toContainText("52.500000, 13.400000")
  await expect
    .poll(() =>
      page.evaluate(() => {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#maps-maplibre-container"),
          "maps--maplibre",
        )
        return controller.map.getZoom()
      }),
    )
    .toBe(16)
})

test("a point takes click priority over an overlapping route", async ({
  page,
}) => {
  await addMergedPoint(page)
  await page.evaluate((coordinates) => {
    const map = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    ).map
    map.removeLayer("tracks-mvt")
    map.addSource("issue-3719-track", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: [
          {
            type: "Feature",
            geometry: {
              type: "LineString",
              coordinates: [
                [coordinates[0] - 0.01, coordinates[1]],
                [coordinates[0] + 0.01, coordinates[1]],
              ],
            },
            properties: { id: 900002 },
          },
        ],
      },
    })
    map.addLayer(
      {
        id: "tracks-mvt",
        type: "line",
        source: "issue-3719-track",
        paint: { "line-width": 16, "line-color": "#ef4444" },
      },
      "points-mvt",
    )
    window.__issue3719TrackSelections = 0
    document.addEventListener("timeline:open-track", () => {
      window.__issue3719TrackSelections += 1
    })
  }, LOCATION)
  await page.waitForFunction((coordinates) => {
    const map = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    ).map
    return ["points-mvt", "tracks-mvt"].every(
      (layer) =>
        map.queryRenderedFeatures(map.project(coordinates), {
          layers: [layer],
        }).length > 0,
    )
  }, LOCATION)

  const position = await markerPosition(page)
  await page.mouse.click(position.x, position.y)
  const info = page.locator('[data-maps--maplibre-target="infoDisplay"]')
  await expect(info).toContainText("52.500000, 13.400000")
  expect(await page.evaluate(() => window.__issue3719TrackSelections)).toBe(0)
})
