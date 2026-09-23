import { expect, test } from "@playwright/test"

const START = [13.4, 52.5]
const MIDDLE = [13.4005, 52.5]
const END = [13.401, 52.5]
const MOVED = [13.4005, 52.5005]

async function openEditor(page, { selectedGhost = false } = {}) {
  await page.goto("/map/v2")
  await page.waitForFunction(() => {
    const element = document.querySelector("#maps-maplibre-container")
    const controller = window.Stimulus?.getControllerForElementAndIdentifier(
      element,
      "maps--maplibre",
    )
    return controller?.map?.loaded() && controller?.map?.getLayer("tracks-mvt")
  })

  await page.evaluate(
    async ({ start, middle, end, selectedGhost }) => {
      const element = document.querySelector("#maps-maplibre-container")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        element,
        "maps--maplibre",
      )
      const map = controller.map
      map.jumpTo({ center: middle, zoom: 16 })
      const feature = {
        type: "Feature",
        geometry: { type: "LineString", coordinates: [start, middle, end] },
        properties: {
          id: 900001,
          revision: 1,
          segments: [
            {
              id: 1,
              start_index: 0,
              end_index: 1,
              coordinates: [start, middle],
              color: "#ef4444",
            },
            {
              id: 2,
              start_index: 1,
              end_index: 2,
              coordinates: [middle, end],
              color: "#22c55e",
            },
          ],
        },
      }
      const point = (id, coordinates, revision = 1) => ({
        id,
        longitude: String(coordinates[0]),
        latitude: String(coordinates[1]),
        revision,
      })
      if (selectedGhost) {
        const ghost = {
          type: "Feature",
          geometry: { type: "LineString", coordinates: [start, middle] },
          properties: { id: 900002, revision: 1 },
        }
        controller.layerManager.getLayer("tracks").setSelectedTrack(ghost)
        controller.eventHandlers.selectedTrackFeature = ghost
      }
      const editor = await controller.eventHandlers._mapEditor()
      editor.apiClient = {
        fetchTrackWithSegments: async () => structuredClone(feature),
        fetchTrackPoints: async () => [
          point(1, start),
          point(2, middle),
          point(3, end),
        ],
        movePointPosition: async (_id, position) => ({
          point: point(
            2,
            [Number(position.longitude), Number(position.latitude)],
            2,
          ),
          track: {
            ...structuredClone(feature),
            geometry: {
              type: "LineString",
              coordinates: [
                start,
                [Number(position.longitude), Number(position.latitude)],
                end,
              ],
            },
            properties: {
              ...feature.properties,
              revision: 2,
              segments: [
                {
                  ...feature.properties.segments[0],
                  coordinates: [
                    start,
                    [Number(position.longitude), Number(position.latitude)],
                  ],
                },
                {
                  ...feature.properties.segments[1],
                  coordinates: [
                    [Number(position.longitude), Number(position.latitude)],
                    end,
                  ],
                },
              ],
            },
          },
          revision: { point: 2, track: 2 },
        }),
      }
      editor.setEditable(true)
      controller.eventHandlers.pointDrag.isEnabled = () => true
      await editor.selectTrack(900001, { forEditing: true })
    },
    { start: START, middle: MIDDLE, end: END, selectedGhost },
  )
  await page.waitForFunction((middle) => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    return (
      controller.map.queryRenderedFeatures(controller.map.project(middle), {
        layers: ["track-points"],
      }).length > 0
    )
  }, MIDDLE)
}

async function mapPoint(page, coordinates) {
  return page.evaluate((value) => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    const projected = controller.map.project(value)
    const rect = controller.map.getCanvas().getBoundingClientRect()
    return { x: rect.left + projected.x, y: rect.top + projected.y }
  }, coordinates)
}

async function dragMiddlePoint(page) {
  await page.evaluate(async (moved) => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    const editor = controller.layerManager.getLayer("map-editor")
    if (!editor.startDrag(2)) throw new Error("Point drag could not start")
    editor.dragTo(...moved)
    await editor.endDrag({ lng: moved[0], lat: moved[1] })
  }, MOVED)
  await expect(page.getByTestId("point-edit-history")).toBeVisible()
}

test("dragged track segments keep their own colors without a duplicate base edge", async ({
  page,
}) => {
  await openEditor(page)
  await dragMiddlePoint(page)
  const features = await page.evaluate(
    ({ start, moved }) => {
      const map = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("#maps-maplibre-container"),
        "maps--maplibre",
      ).map
      const midpoint = map.project([
        (start[0] + moved[0]) / 2,
        (start[1] + moved[1]) / 2,
      ])
      return map
        .queryRenderedFeatures(midpoint, {
          layers: ["editable-track-line", "editable-track-segments"],
        })
        .map((feature) => ({
          layer: feature.layer.id,
          color: feature.properties.color,
        }))
    },
    { start: START, moved: MOVED },
  )
  expect(features).toContainEqual({
    layer: "editable-track-segments",
    color: "#ef4444",
  })
  expect(features.map((feature) => feature.layer)).not.toContain(
    "editable-track-line",
  )
})

test("moving a point clears the previously selected track and keeps old tile edges excluded", async ({
  page,
}) => {
  await openEditor(page, { selectedGhost: true })
  await dragMiddlePoint(page)
  const state = await page.evaluate(() => {
    const controller = window.Stimulus.getControllerForElementAndIdentifier(
      document.querySelector("#maps-maplibre-container"),
      "maps--maplibre",
    )
    return {
      selected: controller.layerManager.getLayer("tracks").selectedFeature,
      filter: controller.map.getFilter("tracks-mvt"),
    }
  })
  expect(state.selected).toBeNull()
  expect(JSON.stringify(state.filter)).toContain("900001")
})

test("the edit history stays on the visible side of the map panel", async ({
  page,
}) => {
  await openEditor(page)
  await dragMiddlePoint(page)
  await page.getByRole("button", { name: "Layers", exact: true }).click()
  const history = page.getByTestId("point-edit-history")
  await expect(history).toBeVisible()
  await expect(history.getByRole("button", { name: "Undo" })).toBeVisible()
  await expect(history.getByRole("button", { name: "Redo" })).toBeVisible()
  await expect(history.locator("xpath=..")).toHaveClass(
    /maplibregl-ctrl-bottom-right/,
  )
})

test("an editable point shows a grab cursor on hover", async ({ page }) => {
  await openEditor(page)
  const position = await mapPoint(page, MIDDLE)
  await page.mouse.move(position.x, position.y)
  await expect
    .poll(() =>
      page
        .locator(".maplibregl-canvas")
        .evaluate((canvas) => canvas.style.cursor),
    )
    .toBe("grab")
})

test("dragging a rendered point with the mouse saves its new position", async ({
  page,
}) => {
  await openEditor(page)
  const from = await mapPoint(page, MIDDLE)
  const to = await mapPoint(page, MOVED)
  await page.mouse.move(from.x, from.y)
  await page.mouse.down()
  await page.mouse.move(to.x, to.y, { steps: 8 })
  await page.mouse.up()

  await expect(page.getByTestId("point-edit-history")).toContainText("1")
  await expect
    .poll(() =>
      page.evaluate((moved) => {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#maps-maplibre-container"),
          "maps--maplibre",
        )
        const editor = controller.layerManager.getLayer("map-editor")
        const coordinates = editor._point(2).geometry.coordinates
        return coordinates.every(
          (value, index) => Math.abs(value - moved[index]) < 0.00001,
        )
      }, MOVED),
    )
    .toBe(true)
})
