import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "./helpers/navigation.js"
import { API_KEYS } from "./v2/helpers/constants.js"
import { waitForMapLibre } from "./v2/helpers/setup.js"

let original
test.beforeEach(async ({ page }) => {
  const response = await page.request.get("/native/map/data/settings")
  expect(response.ok()).toBe(true)
  original = (await response.json()).settings
})
test.afterEach(async ({ page }) => {
  const response = await page.request.patch("/api/v1/settings", {
    headers: { Authorization: `Bearer ${API_KEYS.DEMO_USER}` },
    data: {
      settings: {
        enabled_map_layers: original.enabled_map_layers,
        point_dragging_enabled: original.point_dragging_enabled,
      },
    },
  })
  expect(response.ok()).toBe(true)
})

const START = [13.4, 52.5]
const MIDDLE = [13.4005, 52.5]
const END = [13.401, 52.5]
const MOVED = [13.4005, 52.5005]

async function openEditor(
  page,
  { selectedGhost = false, partialSegments = false } = {},
) {
  await page.goto("/map/v2?locale=en")
  await closeOnboardingModal(page)
  await waitForMapLibre(page)
  const edit = page.getByTestId("native-edit-points")
  if (!(await edit.isChecked())) {
    await page.getByTestId("map-button-layers").click()
    const points = page.getByTestId("map-layer-points")
    if (!(await points.isChecked())) await points.locator("xpath=..").click()
    await expect(edit).toBeVisible()
    await edit.click()
    await page.locator("#native-map-panel-close").click()
    await expect(page.locator("#map-settings-panel")).not.toHaveClass(
      /\bopen\b/,
    )
    await expect
      .poll(() =>
        page.locator("#native-map").evaluate((element) => {
          const panel = document.querySelector("#map-settings-panel")
          const canvas = element.querySelector("canvas.maplibregl-canvas")
          return (
            panel.getBoundingClientRect().right <= 0 &&
            Math.abs(
              canvas.getBoundingClientRect().width -
                element.getBoundingClientRect().width,
            ) < 1
          )
        }),
      )
      .toBe(true)
  }
  await expect(edit).toBeChecked()
  await waitForMapLibre(page)

  await page.evaluate(
    async ({ start, middle, end, selectedGhost, partialSegments }) => {
      const element = document.querySelector("#native-map")
      const controller = window.liveSocket
        ?.getViewByEl(element.closest("[data-phx-session]"))
        ?.getHook(element)?.mapOwner
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
      if (partialSegments)
        feature.properties.segments = feature.properties.segments.slice(0, 1)
      if (selectedGhost) {
        const ghost = {
          type: "Feature",
          geometry: { type: "LineString", coordinates: [start, middle] },
          properties: { id: 900002, revision: 1 },
        }
        controller.map.addSource("native-selected-track", {
          type: "geojson",
          data: ghost,
        })
        controller.map.addLayer({
          id: "native-selected-track-line",
          source: "native-selected-track",
          type: "line",
          paint: { "line-color": "#f00" },
        })
      }
      const editor = controller.editor
      Object.assign(editor, {
        readTrack: async () => structuredClone(feature),
        readPoints: async () => [
          point(1, start),
          point(2, middle),
          point(3, end),
        ],
        move: async (_id, position) => ({
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
                ...(!partialSegments
                  ? [
                      {
                        ...feature.properties.segments[1],
                        coordinates: [
                          [
                            Number(position.longitude),
                            Number(position.latitude),
                          ],
                          end,
                        ],
                      },
                    ]
                  : []),
              ],
            },
          },
          revision: { point: 2, track: 2 },
        }),
      })
      editor.setEditable(true)
      await editor.selectTrack(900001, { forEditing: true })
    },
    { start: START, middle: MIDDLE, end: END, selectedGhost, partialSegments },
  )
  await page.waitForFunction((middle) => {
    const controller = (() => {
      const el = document.querySelector("#native-map")
      return window.liveSocket
        ?.getViewByEl(el.closest("[data-phx-session]"))
        ?.getHook(el)?.mapOwner
    })()
    return (
      controller.map.queryRenderedFeatures(controller.map.project(middle), {
        layers: ["track-points"],
      }).length > 0
    )
  }, MIDDLE)
}

async function mapPoint(page, coordinates) {
  return page.evaluate((value) => {
    const controller = (() => {
      const el = document.querySelector("#native-map")
      return window.liveSocket
        ?.getViewByEl(el.closest("[data-phx-session]"))
        ?.getHook(el)?.mapOwner
    })()
    const projected = controller.map.project(value)
    const rect = controller.map.getCanvas().getBoundingClientRect()
    return { x: rect.left + projected.x, y: rect.top + projected.y }
  }, coordinates)
}

async function dragMiddlePoint(page) {
  await page.evaluate(async (moved) => {
    const controller = (() => {
      const el = document.querySelector("#native-map")
      return window.liveSocket
        ?.getViewByEl(el.closest("[data-phx-session]"))
        ?.getHook(el)?.mapOwner
    })()
    const editor = controller.editor
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
  const renderedFeatures = () =>
    page.evaluate(
      ({ start, moved }) => {
        const map = (() => {
          const el = document.querySelector("#native-map")
          return window.liveSocket
            ?.getViewByEl(el.closest("[data-phx-session]"))
            ?.getHook(el)?.mapOwner
        })().map
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
  await expect.poll(renderedFeatures).toContainEqual({
    layer: "editable-track-segments",
    color: "#ef4444",
  })
  const features = await renderedFeatures()
  expect(features.map((feature) => feature.layer)).not.toContain(
    "editable-track-line",
  )
})

test("a partially segmented track keeps its uncovered edge after a point moves", async ({
  page,
}) => {
  await openEditor(page, { partialSegments: true })
  await dragMiddlePoint(page)
  const renderedLayers = () =>
    page.evaluate(
      ({ moved, end }) => {
        const map = (() => {
          const el = document.querySelector("#native-map")
          return window.liveSocket
            ?.getViewByEl(el.closest("[data-phx-session]"))
            ?.getHook(el)?.mapOwner
        })().map
        const midpoint = map.project([
          (moved[0] + end[0]) / 2,
          (moved[1] + end[1]) / 2,
        ])
        return map
          .queryRenderedFeatures(midpoint, {
            layers: ["editable-track-line", "editable-track-segments"],
          })
          .map((feature) => feature.layer.id)
      },
      { moved: MOVED, end: END },
    )
  await expect.poll(renderedLayers).toContain("editable-track-line")
  expect(await renderedLayers()).not.toContain("editable-track-segments")
})

test("moving a point clears the previously selected track and keeps old tile edges excluded", async ({
  page,
}) => {
  await openEditor(page, { selectedGhost: true })
  await dragMiddlePoint(page)
  const state = await page.evaluate(() => {
    const controller = (() => {
      const el = document.querySelector("#native-map")
      return window.liveSocket
        ?.getViewByEl(el.closest("[data-phx-session]"))
        ?.getHook(el)?.mapOwner
    })()
    return {
      selected: controller.map.getSource("native-selected-track") ?? null,
      filter: controller.map.getFilter("tracks-mvt"),
    }
  })
  expect(state.selected).toBeNull()
  expect(JSON.stringify(state.filter)).toContain("900001")
})

test("turning editing off clears an editor opened after a track was selected", async ({
  page,
}) => {
  await openEditor(page, { selectedGhost: true })
  const state = await page.evaluate(() => {
    const controller = (() => {
      const el = document.querySelector("#native-map")
      return window.liveSocket
        ?.getViewByEl(el.closest("[data-phx-session]"))
        ?.getHook(el)?.mapOwner
    })()
    const editor = controller.editor
    const editingBefore = editor.forEditing
    editor.setEditable(false)
    return { editingBefore, dataAfter: editor.data }
  })
  expect(state.editingBefore).toBe(true)
  expect(state.dataAfter).toBeNull()
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
        const controller = (() => {
          const el = document.querySelector("#native-map")
          return window.liveSocket
            ?.getViewByEl(el.closest("[data-phx-session]"))
            ?.getHook(el)?.mapOwner
        })()
        const editor = controller.editor
        const coordinates = editor._point(2).geometry.coordinates
        return coordinates.every(
          (value, index) => Math.abs(value - moved[index]) < 0.00001,
        )
      }, MOVED),
    )
    .toBe(true)
})
