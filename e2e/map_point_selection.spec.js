import { expect, test } from "@playwright/test"

const LOCATION = [13.4, 52.5]

async function addPointMarker(page, { count = 2, zoom = 16 } = {}) {
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
  await page.evaluate(
    ({ coordinates, count, zoom }) => {
      const map = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("#maps-maplibre-container"),
        "maps--maplibre",
      ).map
      map.jumpTo({ center: coordinates, zoom })
      map.removeLayer("points-mvt")
      map.addSource("selection-points", {
        type: "geojson",
        data: {
          type: "FeatureCollection",
          features: [
            {
              type: "Feature",
              geometry: { type: "Point", coordinates },
              properties: {
                id: 900001,
                count,
                timestamp: 1_700_000_000,
                longitude: String(coordinates[0]),
                latitude: String(coordinates[1]),
              },
            },
          ],
        },
      })
      map.addLayer({
        id: "points-mvt",
        type: "circle",
        source: "selection-points",
        paint: { "circle-radius": 9, "circle-color": "#3b82f6" },
      })
    },
    { coordinates: LOCATION, count, zoom },
  )
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

async function mapZoom(page) {
  return page.evaluate(() => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    return controller.map.getZoom()
  })
}

test("a merged marker zooms until a single point can be selected", async ({
  page,
}) => {
  await addPointMarker(page)
  let position = await markerPosition(page)
  await page.mouse.move(position.x, position.y)
  await expect
    .poll(() =>
      page
        .locator(".maplibregl-canvas")
        .evaluate((canvas) => canvas.style.cursor),
    )
    .toBe("zoom-in")
  await page.mouse.click(position.x, position.y)

  const info = page.locator('[data-maps--maplibre-target="infoDisplay"]')
  await expect.poll(() => mapZoom(page)).toBe(18)
  await expect(info.getByRole("button", { name: "Delete" })).toHaveCount(0)

  await page.evaluate((coordinates) => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    controller.map.getSource("selection-points").setData({
      type: "FeatureCollection",
      features: [
        {
          type: "Feature",
          geometry: { type: "Point", coordinates },
          properties: {
            id: 900001,
            count: 1,
            timestamp: 1_700_000_000,
            longitude: String(coordinates[0]),
            latitude: String(coordinates[1]),
          },
        },
      ],
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
      })[0]?.properties.count === 1
    )
  }, LOCATION)
  position = await markerPosition(page)
  await page.mouse.click(position.x, position.y)

  await expect(info).toBeVisible()
  await expect(info.getByRole("button", { name: "Delete" })).toBeVisible()
  await expect(info).toContainText("52.500000, 13.400000")
})

test("overlapping points at maximum zoom cannot delete an arbitrary point", async ({
  page,
}) => {
  await addPointMarker(page, { zoom: 22 })
  const position = await markerPosition(page)
  await page.mouse.click(position.x, position.y)

  const info = page.locator('[data-maps--maplibre-target="infoDisplay"]')
  await expect(info).toContainText("2 overlapping points")
  await expect(info.getByRole("button", { name: "Delete" })).toHaveCount(0)
  expect(await mapZoom(page)).toBe(22)
})

test("a point takes click priority over an overlapping route", async ({
  page,
}) => {
  await addPointMarker(page, { count: 1 })
  await page.evaluate((coordinates) => {
    const map = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    ).map
    map.removeLayer("tracks-mvt")
    map.addSource("overlapping-route", {
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
        source: "overlapping-route",
        paint: { "line-width": 16, "line-color": "#ef4444" },
      },
      "points-mvt",
    )
    window.__overlappingTrackSelections = 0
    document.addEventListener("timeline:open-track", () => {
      window.__overlappingTrackSelections += 1
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
  expect(await page.evaluate(() => window.__overlappingTrackSelections)).toBe(0)
})
