import { readFile } from "node:fs/promises"
import { expect, test } from "@playwright/test"
import {
  blockOutboundAndStubBasemap,
  controllerState,
  waitForMapController,
} from "./helpers.js"

async function seedData() {
  return JSON.parse(await readFile("e2e/temp/seed.json", "utf8"))
}

async function openMap(page) {
  const seed = await seedData()
  await blockOutboundAndStubBasemap(page)
  const { start_at: startAt, end_at: endAt } = seed.history_scope
  await page.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
  )
  await waitForMapController(page)
  return seed
}

test("tile-only sources load offline without classic history requests", async ({
  page,
}) => {
  const requests = []
  const consoleMessages = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  page.on("console", (message) => consoleMessages.push(message.text()))
  await openMap(page)
  const state = await controllerState(page)

  expect(state.sourceIds).toContain("points-mvt-source")
  expect(state.sourceIds).toContain("tracks-mvt-source")
  expect(
    state.sourceIds,
    `Browser console:\n${consoleMessages.join("\n")}`,
  ).toContain("scratch-source")
  expect(state.layerIds).toContain("points-mvt")
  expect(state.layerIds).toContain("tracks-mvt")
  expect(state.layerIds).not.toContain("routes")
  expect(requests.some((path) => path === "/api/v1/points")).toBe(false)
  expect(requests.some((path) => path === "/api/v1/tracks")).toBe(false)
  expect(requests.some((path) => path === "/maps/countries-v1.pmtiles")).toBe(
    true,
  )
})

test("selected import scopes Point, Track, and Visited Countries requests", async ({
  page,
}) => {
  const seed = await seedData()
  const scopedRequests = []
  page.on("request", (request) => {
    const url = new URL(request.url())
    if (
      url.pathname.startsWith("/api/v1/tiles/points/") ||
      url.pathname.startsWith("/api/v1/tiles/tracks/") ||
      url.pathname === "/api/v1/countries/visited"
    ) {
      scopedRequests.push(url.href)
    }
  })
  await blockOutboundAndStubBasemap(page)
  const { start_at: startAt, end_at: endAt } = seed.history_scope

  await page.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}&import_id=${seed.import_id}`,
  )
  await waitForMapController(page)
  await expect
    .poll(
      () =>
        new Set(
          scopedRequests.map((value) => {
            const path = new URL(value).pathname
            if (path.startsWith("/api/v1/tiles/points/")) return "points"
            if (path.startsWith("/api/v1/tiles/tracks/")) return "tracks"
            return "countries"
          }),
        ).size,
    )
    .toBe(3)

  for (const value of scopedRequests) {
    expect(new URL(value).searchParams.get("import_id")).toBe(
      String(seed.import_id),
    )
  }
})

test("tile-backed heatmap and fog coexist with bounded tools and timeline", async ({
  page,
}) => {
  const seed = await openMap(page)
  const pointRequests = []
  const trackRequests = []
  const timelineRequests = []
  page.on("request", (request) => {
    const url = new URL(request.url())
    if (url.pathname === "/api/v1/points") pointRequests.push(url.href)
    if (url.pathname === `/api/v1/tracks/${seed.track_id}`) {
      trackRequests.push(url.href)
    }
    if (url.pathname === "/map/timeline_feeds") {
      timelineRequests.push(url.href)
    }
  })

  const result = await page.evaluate(
    async ({ trackId }) => {
      const element = document.querySelector("#maps-maplibre-container")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      const points = controller.layerManager.getLayer("points-mvt")
      const fog = controller.layerManager.getLayer("fog")
      const initial = {
        heatmapVisible: points.heatmapVisible,
        heatmapLayout: controller.map.getLayoutProperty(
          "points-mvt-heatmap",
          "visibility",
        ),
        fogVisible: fog.visible,
        fogUsesTiles: fog.tiledSource,
      }

      await controller.startSelectArea()
      await controller.areaSelectionManager.handleAreaSelected({
        minLng: -0.1,
        maxLng: 0.1,
        minLat: -0.1,
        maxLat: 0.1,
      })
      const selectedPointCount =
        controller.areaSelectionManager.selectedPointsLayer?.data?.features
          ?.length || 0
      controller.cancelAreaSelection()

      await controller.toggleReplay()
      const replay = {
        open: controller.replayPanel?.isOpen === true,
        hasData: controller.replayPanel?.manager?.hasData() === true,
        markerSource: Boolean(controller.map.getSource("replay-marker-source")),
      }
      await controller.toggleReplay()

      await controller.handleEntryClick({
        detail: { trackId, startedAt: null },
      })
      const focusedTrackId =
        controller.layerManager.getLayer("tracks")?.selectedFeature?.properties
          ?.id

      controller.loadTimelineFeed()

      return { initial, selectedPointCount, replay, focusedTrackId }
    },
    { trackId: seed.track_id },
  )

  expect(result.initial).toEqual({
    heatmapVisible: true,
    heatmapLayout: "visible",
    fogVisible: true,
    fogUsesTiles: true,
  })
  expect(result.selectedPointCount).toBe(3)
  expect(result.replay).toEqual({
    open: true,
    hasData: true,
    markerSource: true,
  })
  expect(String(result.focusedTrackId)).toBe(String(seed.track_id))

  await expect.poll(() => timelineRequests.length).toBeGreaterThan(0)
  expect(trackRequests).toHaveLength(1)
  expect(pointRequests.length).toBeGreaterThanOrEqual(2)
  for (const value of pointRequests) {
    const params = new URL(value).searchParams
    expect(params.has("start_at")).toBe(true)
    expect(params.has("end_at")).toBe(true)
    if (params.has("min_longitude")) {
      expect(params.get("per_page")).toBe("10000")
      expect(params.has("max_longitude")).toBe(true)
      expect(params.has("min_latitude")).toBe(true)
      expect(params.has("max_latitude")).toBe(true)
    }
  }
})

test("sequential edits return canonical tracks and show a success pulse", async ({
  page,
}) => {
  const seed = await openMap(page)
  const moveResponses = []
  const moveBodies = []
  const moveRequests = []
  page.on("request", (request) => {
    if (new URL(request.url()).pathname.endsWith("/position")) {
      moveRequests.push(request.postDataJSON())
    }
  })
  page.on("response", async (response) => {
    if (new URL(response.url()).pathname.endsWith("/position")) {
      moveResponses.push(response.status())
      moveBodies.push(await response.json())
    }
  })

  const result = await page.evaluate(
    async ({ trackId }) => {
      const element = document.querySelector("#maps-maplibre-container")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      const editor = await controller.eventHandlers._mapEditor()
      await editor.selectTrack(trackId)
      const point = editor.data.features.find(
        (feature) => feature.properties.kind === "point",
      )
      const beforeRevision = Number(point.properties.revision)
      const beforeTrackRevision = editor.trackRevision
      const [longitude, latitude] = point.geometry.coordinates

      editor.onMouseDown({ features: [point], preventDefault() {} })
      editor.onMouseMove({
        lngLat: { lng: longitude + 0.001, lat: latitude + 0.001 },
      })
      await editor.onMouseUp({
        lngLat: { lng: longitude + 0.001, lat: latitude + 0.001 },
      })

      const firstRevision = Number(
        editor._point(point.properties.id).properties.revision,
      )
      const firstTrackRevision = editor.trackRevision
      const canonicalLength = editor._track().geometry.coordinates.length
      const pulseFilter = controller.map.getFilter("edit-success-indicator")

      const secondPoint = editor._points()[1]
      const [secondLongitude, secondLatitude] = secondPoint.geometry.coordinates
      editor.onMouseDown({ features: [secondPoint], preventDefault() {} })
      editor.onMouseMove({
        lngLat: { lng: secondLongitude + 0.001, lat: secondLatitude + 0.001 },
      })
      await editor.onMouseUp({
        lngLat: { lng: secondLongitude + 0.001, lat: secondLatitude + 0.001 },
      })

      return {
        beforeRevision,
        beforeTrackRevision,
        firstRevision,
        firstTrackRevision,
        finalTrackRevision: editor.trackRevision,
        canonicalLength,
        pulseFilter,
        sessionStillOpen: editor.data !== null,
        inFlight: editor.inFlight,
      }
    },
    { trackId: seed.track_id },
  )

  await expect.poll(() => moveBodies.length).toBe(2)
  expect(
    moveResponses,
    JSON.stringify({ requests: moveRequests, responses: moveBodies }, null, 2),
  ).toEqual([200, 200])
  expect(result.firstRevision).toBeGreaterThan(result.beforeRevision)
  expect(result.firstTrackRevision).toBeGreaterThan(result.beforeTrackRevision)
  expect(result.finalTrackRevision).toBeGreaterThan(result.firstTrackRevision)
  expect(result.canonicalLength).toBe(3)
  expect(result.pulseFilter).not.toEqual(["==", ["get", "id"], -1])
  expect(result.sessionStillOpen).toBe(true)
  expect(result.inFlight).toBe(false)
  await expect(page.locator(".toast-success")).toHaveCount(0)
})

test("a stale second session receives 409 and reconciles to the winner", async ({
  browser,
}) => {
  const seed = await seedData()
  const storageState = "e2e/temp/.auth/user.json"
  const contexts = await Promise.all([
    browser.newContext({ storageState }),
    browser.newContext({ storageState }),
  ])
  const pages = await Promise.all(contexts.map((context) => context.newPage()))
  try {
    await Promise.all(pages.map((page) => blockOutboundAndStubBasemap(page)))
    // Model a temporarily offline second session: it keeps the revisions it
    // selected with and must reconcile the server's 409 canonical payload.
    await pages[1].routeWebSocket("**/cable", () => {})
    const { start_at: startAt, end_at: endAt } = seed.history_scope
    const url = `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`
    await Promise.all(pages.map((page) => page.goto(url)))
    await Promise.all(pages.map((page) => waitForMapController(page)))
    await Promise.all(
      pages.map((page) =>
        page.evaluate(async (trackId) => {
          const element = document.querySelector("#maps-maplibre-container")
          const controller =
            window.Stimulus.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
          const editor = await controller.eventHandlers._mapEditor()
          await editor.selectTrack(trackId)
        }, seed.track_id),
      ),
    )

    const statuses = []
    pages[1].on("response", (response) => {
      if (new URL(response.url()).pathname.endsWith("/position")) {
        statuses.push(response.status())
      }
    })
    const winner = await moveFirstPoint(pages[0], 0.001)
    const stale = await moveFirstPoint(pages[1], 0.002)

    expect(statuses).toContain(409)
    expect(stale.coordinates).toEqual(winner.coordinates)
    expect(stale.trackRevision).toBe(winner.trackRevision)
    await expect(pages[1].locator(".toast-error")).toBeVisible()
  } finally {
    await Promise.all(contexts.map((context) => context.close()))
  }
})

test("country membership updates in the same successful move", async ({
  page,
  browser,
}) => {
  const seed = await openMap(page)
  const secondContext = await browser.newContext({
    storageState: "e2e/temp/.auth/user.json",
  })
  const secondPage = await secondContext.newPage()
  await blockOutboundAndStubBasemap(secondPage)
  const { start_at: startAt, end_at: endAt } = seed.history_scope
  await secondPage.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
  )
  await waitForMapController(secondPage)
  await expect
    .poll(
      () =>
        secondPage.evaluate(() => {
          const element = document.querySelector("#maps-maplibre-container")
          const realtime = window.Stimulus.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre-realtime",
          )
          return realtime?.connectedChannels?.has("mapEdits") === true
        }),
      { timeout: 15_000 },
    )
    .toBe(true)

  try {
    const result = await page.evaluate(
      async ({ pointId, pointRevision }) => {
        const element = document.querySelector("#maps-maplibre-container")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const editor = await controller.eventHandlers._mapEditor()
        editor.selectPoint({
          type: "Feature",
          geometry: { type: "Point", coordinates: [13.5, 52.5] },
          properties: {
            id: pointId,
            longitude: 13.5,
            latitude: 52.5,
            revision: pointRevision,
            count: 1,
          },
        })
        const before = [
          ...controller.layerManager.getLayer("scratch").visitedIsoA3,
        ]
        const point = editor._point(pointId)
        editor.onMouseDown({ features: [point], preventDefault() {} })
        editor.onMouseMove({ lngLat: { lng: 2.35, lat: 48.85 } })
        await editor.onMouseUp({ lngLat: { lng: 2.35, lat: 48.85 } })
        const after = [
          ...controller.layerManager.getLayer("scratch").visitedIsoA3,
        ]
        return {
          before,
          after,
          coordinates: editor._point(pointId).geometry.coordinates,
        }
      },
      {
        pointId: seed.country_point_id,
        pointRevision: seed.country_point_revision,
      },
    )

    expect(result.before).toContain("DEU")
    expect(result.after).toContain("FRA")
    expect(result.after).not.toContain("DEU")
    expect(result.coordinates).toEqual([2.35, 48.85])
    await expect
      .poll(() =>
        secondPage.evaluate(() => {
          const element = document.querySelector("#maps-maplibre-container")
          const controller =
            window.Stimulus.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
          return controller.layerManager.getLayer("scratch")?.visitedIsoA3
        }),
      )
      .toEqual(["FRA"])
  } finally {
    await secondContext.close()
  }
})

test("failed point mutation restores the complete focused overlay", async ({
  page,
}) => {
  const seed = await openMap(page)
  await page.route("**/api/v1/points/*/position", (route) =>
    route.fulfill({
      status: 503,
      contentType: "application/json",
      json: { error: { code: "forced_failure", message: "forced failure" } },
    }),
  )

  const state = await page.evaluate(async (trackId) => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    const editor = await controller.eventHandlers._mapEditor()
    await editor.selectTrack(trackId)
    const before = JSON.parse(JSON.stringify(editor.data))
    const point = editor._points()[0]
    const [longitude, latitude] = point.geometry.coordinates
    editor.onMouseDown({ features: [point], preventDefault() {} })
    editor.onMouseMove({ lngLat: { lng: longitude + 1, lat: latitude + 1 } })
    await editor.onMouseUp({
      lngLat: { lng: longitude + 1, lat: latitude + 1 },
    })
    return {
      before,
      after: editor.data,
      inFlight: editor.inFlight,
      successFilter: controller.map.getFilter("edit-success-indicator"),
    }
  }, seed.track_id)

  expect(state.after).toEqual(state.before)
  expect(state.inFlight).toBe(false)
  expect(state.successFilter).toEqual(["==", ["get", "id"], -1])
  await expect(page.locator(".toast-error")).toBeVisible()
  await expect(page.locator(".toast-success")).toHaveCount(0)
})

test("point tile failures offer retry without a classic fallback", async ({
  page,
}) => {
  const requests = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  await openMap(page)

  let fail = true
  let attempts = 0
  await page.route(/\/api\/v1\/tiles\/points\//, async (route) => {
    attempts += 1
    if (fail) {
      await route.fulfill({
        status: 503,
        contentType: "application/vnd.mapbox-vector-tile",
        body: "",
      })
    } else {
      await route.continue()
    }
  })

  await page.evaluate(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    controller.layerManager.getLayer("points-mvt").refresh()
  })

  await expect.poll(() => attempts).toBeGreaterThan(0)
  const retry = page.locator(".toast-error button").last()
  await expect(retry).toBeVisible()
  fail = false
  await retry.click()
  await expect.poll(() => attempts).toBeGreaterThan(1)

  expect(requests.some((path) => path === "/api/v1/points")).toBe(false)
  expect(requests.some((path) => path === "/api/v1/tracks")).toBe(false)
})

test("Track tile failures offer retry without a classic fallback", async ({
  page,
}) => {
  const requests = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  await openMap(page)

  let fail = true
  let attempts = 0
  await page.route(/\/api\/v1\/tiles\/tracks\//, async (route) => {
    attempts += 1
    if (fail) {
      await route.fulfill({
        status: 503,
        contentType: "application/vnd.mapbox-vector-tile",
        body: "",
      })
    } else {
      await route.continue()
    }
  })

  await page.evaluate(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    controller.layerManager.getLayer("tracks-mvt").refresh()
  })

  await expect.poll(() => attempts).toBeGreaterThan(0)
  const retry = page.locator(".toast-error button").last()
  await expect(retry).toBeVisible()
  fail = false
  await retry.click()
  await expect.poll(() => attempts).toBeGreaterThan(1)

  expect(requests.some((path) => path === "/api/v1/points")).toBe(false)
  expect(requests.some((path) => path === "/api/v1/tracks")).toBe(false)
})

test("Visited Countries metadata failure retries into bundled PMTiles", async ({
  page,
}) => {
  const seed = await seedData()
  await blockOutboundAndStubBasemap(page)
  let fail = true
  let attempts = 0
  await page.route(/\/api\/v1\/countries\/visited(?:\?|$)/, async (route) => {
    attempts += 1
    if (fail) {
      await route.fulfill({
        status: 503,
        contentType: "application/json",
        json: { error: "forced failure" },
      })
    } else {
      await route.continue()
    }
  })

  const { start_at: startAt, end_at: endAt } = seed.history_scope
  await page.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
  )
  await waitForMapController(page)
  const retry = page.locator(".toast-error button").last()
  await expect(retry).toBeVisible()
  fail = false
  await retry.click()

  await expect.poll(() => attempts).toBeGreaterThan(1)
  await expect
    .poll(() =>
      page.evaluate(() => {
        const element = document.querySelector("#maps-maplibre-container")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return Boolean(
          controller.map.getSource("scratch-source") &&
            controller.layerManager.getLayer("scratch"),
        )
      }),
    )
    .toBe(true)
})

test("bundled PMTiles failure offers retry without a history fallback", async ({
  page,
}) => {
  const requests = []
  page.on("request", (request) =>
    requests.push(new URL(request.url()).pathname),
  )
  const seed = await seedData()
  await blockOutboundAndStubBasemap(page)
  let fail = true
  let attempts = 0
  await page.route(/\/maps\/countries-v1\.pmtiles(?:\?|$)/, async (route) => {
    attempts += 1
    if (fail) {
      await route.fulfill({ status: 503, body: "forced PMTiles failure" })
    } else {
      await route.continue()
    }
  })

  const { start_at: startAt, end_at: endAt } = seed.history_scope
  await page.goto(
    `/map?start_at=${encodeURIComponent(startAt)}&end_at=${encodeURIComponent(endAt)}`,
  )
  await waitForMapController(page)
  await expect.poll(() => attempts).toBeGreaterThan(0)
  const retry = page.locator(".toast-error button").last()
  await expect(retry).toBeVisible()

  fail = false
  await retry.click()
  await expect.poll(() => attempts).toBeGreaterThan(1)
  await expect
    .poll(() =>
      page.evaluate(() => {
        const element = document.querySelector("#maps-maplibre-container")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return controller.layerManager.getLayer("scratch")?.getSourceConfig()
          .url
      }),
    )
    .toContain("?_=1")

  expect(requests.some((path) => path === "/api/v1/points")).toBe(false)
  expect(requests.some((path) => path === "/api/v1/tracks")).toBe(false)
})

test("style and range changes close overlays without duplicating handlers", async ({
  page,
}) => {
  const seed = await openMap(page)
  const initialHandlers = await delegatedHandlerCounts(page)

  await page.evaluate(async (trackId) => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    const editor = await controller.eventHandlers._mapEditor()
    await editor.selectTrack(trackId)
    window.__styleReloadEditor = editor
    await controller.settingsController.applyMapStyle("dark")
  }, seed.track_id)

  await expect
    .poll(() =>
      page.evaluate(() => {
        const element = document.querySelector("#maps-maplibre-container")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return Boolean(
          window.__styleReloadEditor?.data === null &&
            !controller.layerManager.getLayer("map-editor") &&
            controller.map.getSource("points-mvt-source") &&
            controller.map.getSource("tracks-mvt-source"),
        )
      }),
    )
    .toBe(true)
  expect(await delegatedHandlerCounts(page)).toEqual(initialHandlers)

  await page.evaluate(async (trackId) => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    const editor = await controller.eventHandlers._mapEditor()
    await editor.selectTrack(trackId)
    window.__rangeReloadEditor = editor
    controller.monthChanged({
      target: { value: controller.startDateValue.slice(0, 7) },
    })
  }, seed.track_id)

  await expect
    .poll(() =>
      page.evaluate(
        () =>
          window.__rangeReloadEditor?.data === null &&
          !document
            .querySelector(".maplibregl-canvas")
            ?.matches("[data-stale]"),
      ),
    )
    .toBe(true)
  expect(await delegatedHandlerCounts(page)).toEqual(initialHandlers)
  expect(
    await page.evaluate(() => {
      const element = document.querySelector("#maps-maplibre-container")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      return {
        editSource: Boolean(controller.map.getSource("editable-track-source")),
        editLayer: Boolean(controller.map.getLayer("track-points")),
      }
    }),
  ).toEqual({ editSource: false, editLayer: false })
})

test("reduced motion uses a static outline and clears it", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" })
  const seed = await openMap(page)
  const pointId = seed.track_point_ids[2]
  const during = await page.evaluate(
    async ({ trackId, pointId }) => {
      const element = document.querySelector("#maps-maplibre-container")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      const editor = await controller.eventHandlers._mapEditor()
      await editor.selectTrack(trackId)
      const point = editor._point(pointId)
      const [longitude, latitude] = point.geometry.coordinates
      editor.onMouseDown({ features: [point], preventDefault() {} })
      editor.onMouseMove({ lngLat: { lng: longitude + 0.001, lat: latitude } })
      await editor.onMouseUp({
        lngLat: { lng: longitude + 0.001, lat: latitude },
      })
      return {
        radius: controller.map.getPaintProperty(
          "edit-success-indicator",
          "circle-radius",
        ),
        opacity: controller.map.getPaintProperty(
          "edit-success-indicator",
          "circle-stroke-opacity",
        ),
      }
    },
    { trackId: seed.track_id, pointId },
  )

  expect(during).toEqual({ radius: 12, opacity: 1 })
  await page.waitForTimeout(850)
  const opacity = await page.evaluate(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    return controller.map.getPaintProperty(
      "edit-success-indicator",
      "circle-stroke-opacity",
    )
  })
  expect(opacity).toBe(0)
})

async function moveFirstPoint(page, delta) {
  return page.evaluate(async (offset) => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    const editor = controller.layerManager.getLayer("map-editor")
    const point = editor._points()[0]
    const [longitude, latitude] = point.geometry.coordinates
    editor.onMouseDown({ features: [point], preventDefault() {} })
    editor.onMouseMove({ lngLat: { lng: longitude + offset, lat: latitude } })
    await editor.onMouseUp({
      lngLat: { lng: longitude + offset, lat: latitude },
    })
    return {
      coordinates: editor._points()[0].geometry.coordinates,
      trackRevision: editor.trackRevision,
    }
  }, delta)
}

async function delegatedHandlerCounts(page) {
  return page.evaluate(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    return Object.fromEntries(
      Object.entries(controller.map._delegatedListeners || {})
        .filter(([, listeners]) => listeners.length > 0)
        .map(([eventName, listeners]) => [
          eventName,
          listeners.map((listener) => listener.layers.join(",")).sort(),
        ]),
    )
  })
}
