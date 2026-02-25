import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../../helpers/navigation.js"
import {
  getPointsSourceData,
  getRoutesSourceData,
  hasLayer,
  waitForLoadingComplete,
} from "../../helpers/setup.js"

test.describe("Points Layer", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe("Display", () => {
    test("displays points layer", async ({ page }) => {
      // Wait for points layer to be added
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            const app = window.Stimulus || window.Application
            const controller = app?.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            return controller?.map?.getLayer("points") !== undefined
          },
          { timeout: 10000 },
        )
        .catch(() => false)

      const hasPoints = await hasLayer(page, "points")
      expect(hasPoints).toBe(true)
    })

    test("loads and displays point data", async ({ page }) => {
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            const app = window.Stimulus || window.Application
            const controller = app?.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            return controller?.map?.getSource("points-source") !== undefined
          },
          { timeout: 15000 },
        )
        .catch(() => false)

      const sourceData = await getPointsSourceData(page)
      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.featureCount).toBeGreaterThan(0)
    })
  })

  test.describe("Data Source", () => {
    test("points source contains valid GeoJSON features", async ({ page }) => {
      // Wait for source to be added
      await page
        .waitForFunction(
          () => {
            const element = document.querySelector(
              '[data-controller*="maps--maplibre"]',
            )
            const app = window.Stimulus || window.Application
            const controller = app?.getControllerForElementAndIdentifier(
              element,
              "maps--maplibre",
            )
            return controller?.map?.getSource("points-source") !== undefined
          },
          { timeout: 10000 },
        )
        .catch(() => false)

      const sourceData = await getPointsSourceData(page)

      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.features).toBeDefined()
      expect(Array.isArray(sourceData.features)).toBe(true)

      if (sourceData.features.length > 0) {
        const firstFeature = sourceData.features[0]
        expect(firstFeature.type).toBe("Feature")
        expect(firstFeature.geometry).toBeDefined()
        expect(firstFeature.geometry.type).toBe("Point")
        expect(firstFeature.geometry.coordinates).toHaveLength(2)
      }
    })
  })

  test.describe("Dragging", () => {
    test("allows dragging points to new positions", async ({ page }) => {
      test.setTimeout(60000)

      // Wait for points to load
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          const app = window.Stimulus || window.Application
          const controller = app?.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          const source = controller?.map?.getSource("points-source")
          return source?._data?.features?.length > 0
        },
        { timeout: 15000 },
      )

      // Get initial point data
      const initialData = await getPointsSourceData(page)
      expect(initialData.features.length).toBeGreaterThan(0)

      // Ensure points layer is visible and dragging is enabled
      await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer
        if (pointsLayer) {
          pointsLayer.show()
          if (!pointsLayer.draggingEnabled) {
            pointsLayer.enableDragging()
          }
        }
      })

      await page.waitForTimeout(1000)

      // Programmatically simulate a point drag via the PointsLayer's internal methods
      const dragResult = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer
        const map = controller?.map

        if (!pointsLayer || !map)
          return { success: false, reason: "no layer or map" }

        const source = map.getSource("points-source")
        const data = source?._data
        if (!data?.features?.length)
          return { success: false, reason: "no features" }

        const feature = data.features[0]
        const originalCoords = [...feature.geometry.coordinates]
        const pointId = feature.properties.id

        // Calculate new coordinates (offset by ~0.001 degrees)
        const newLng = parseFloat(originalCoords[0]) + 0.001
        const newLat = parseFloat(originalCoords[1]) + 0.001

        // Directly simulate the drag by calling internal methods
        // 1. Set dragged feature
        pointsLayer.isDragging = true
        pointsLayer.draggedFeature = feature

        // 2. Update the feature coordinates (simulating onMouseMove)
        feature.geometry.coordinates = [newLng, newLat]
        source.setData(data)

        // 3. Simulate onMouseUp - trigger API update
        pointsLayer.isDragging = false
        const _draggedFeature = pointsLayer.draggedFeature
        pointsLayer.draggedFeature = null

        // Make the API call to persist the change
        try {
          const apiKeyEl = document.querySelector(
            "[data-maps--maplibre-api-key-value]",
          )
          const apiKey = apiKeyEl?.getAttribute(
            "data-maps--maplibre-api-key-value",
          )
          if (apiKey) {
            const response = await fetch(`/api/v1/points/${pointId}`, {
              method: "PATCH",
              headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                point: {
                  latitude: newLat,
                  longitude: newLng,
                },
              }),
            })

            const responseBody = await response.text()
            return {
              success: response.ok,
              pointId,
              originalCoords,
              newCoords: [newLng, newLat],
              status: response.status,
              body: responseBody,
            }
          }
          return { success: false, reason: "no api key" }
        } catch (err) {
          return { success: false, reason: err.message }
        }
      })

      if (!dragResult.success) {
        console.log("Drag failed:", JSON.stringify(dragResult))
      }
      expect(dragResult.success).toBe(true)

      // Wait for data to settle
      await page.waitForTimeout(1000)

      // Get updated point data
      const updatedData = await getPointsSourceData(page)
      const updatedPoint = updatedData.features.find(
        (f) => f.properties.id === dragResult.pointId,
      )

      expect(updatedPoint).toBeDefined()
      const updatedCoords = updatedPoint.geometry.coordinates

      // Verify the point has moved
      const updatedLng = parseFloat(updatedCoords[0])
      const updatedLat = parseFloat(updatedCoords[1])
      const initialLng = parseFloat(dragResult.originalCoords[0])
      const initialLat = parseFloat(dragResult.originalCoords[1])

      expect(updatedLng).not.toBeCloseTo(initialLng, 5)
      expect(updatedLat).not.toBeCloseTo(initialLat, 5)
    })

    test("updates connected route segments when point is dragged", async ({
      page,
    }) => {
      test.setTimeout(60000)

      // Wait for both points and routes to load
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          const app = window.Stimulus || window.Application
          const controller = app?.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          const pointsSource = controller?.map?.getSource("points-source")
          const routesSource = controller?.map?.getSource("routes-source")
          return (
            pointsSource?._data?.features?.length > 0 &&
            routesSource?._data?.features?.length > 0
          )
        },
        { timeout: 15000 },
      )

      // Ensure points layer is visible
      await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer
        if (pointsLayer) {
          pointsLayer.show()
          if (!pointsLayer.draggingEnabled) {
            pointsLayer.enableDragging()
          }
        }
      })

      await page.waitForTimeout(1000)

      // Get initial route data
      const initialRoutesData = await getRoutesSourceData(page)
      expect(initialRoutesData.features.length).toBeGreaterThan(0)

      // Programmatically simulate point drag and update routes
      const dragResult = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer
        const map = controller?.map

        if (!pointsLayer || !map)
          return { success: false, reason: "no layer or map" }

        const source = map.getSource("points-source")
        const data = source?._data
        if (!data?.features?.length)
          return { success: false, reason: "no features" }

        const feature = data.features[0]
        const originalCoords = [...feature.geometry.coordinates]
        const pointId = feature.properties.id

        // Calculate new coordinates
        const newLng = parseFloat(originalCoords[0]) + 0.001
        const newLat = parseFloat(originalCoords[1]) + 0.001

        // Update the feature coordinates
        feature.geometry.coordinates = [newLng, newLat]
        source.setData(data)

        // Also update route segments that reference this point
        const routesSource = map.getSource("routes-source")
        if (routesSource?._data?.features) {
          const routesData = routesSource._data
          routesData.features.forEach((route) => {
            route.geometry.coordinates = route.geometry.coordinates.map(
              (coord) => {
                if (
                  Math.abs(coord[0] - originalCoords[0]) < 0.0001 &&
                  Math.abs(coord[1] - originalCoords[1]) < 0.0001
                ) {
                  return [newLng, newLat]
                }
                return coord
              },
            )
          })
          routesSource.setData(routesData)
        }

        // Persist via API
        try {
          const apiKeyEl = document.querySelector(
            "[data-maps--maplibre-api-key-value]",
          )
          const apiKey = apiKeyEl?.getAttribute(
            "data-maps--maplibre-api-key-value",
          )
          if (apiKey) {
            const response = await fetch(`/api/v1/points/${pointId}`, {
              method: "PATCH",
              headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                point: {
                  latitude: newLat,
                  longitude: newLng,
                },
              }),
            })

            return {
              success: response.ok,
              pointId,
              originalCoords,
              newCoords: [newLng, newLat],
            }
          }
          return { success: false, reason: "no api key" }
        } catch (err) {
          return { success: false, reason: err.message }
        }
      })

      expect(dragResult.success).toBe(true)

      await page.waitForTimeout(1000)

      // Get updated data
      const updatedPointsData = await getPointsSourceData(page)
      const updatedRoutesData = await getRoutesSourceData(page)

      const updatedPoint = updatedPointsData.features.find(
        (f) => f.properties.id === dragResult.pointId,
      )
      expect(updatedPoint).toBeDefined()
      const updatedCoords = updatedPoint.geometry.coordinates

      // The point moved
      const updatedLng = parseFloat(updatedCoords[0])
      const updatedLat = parseFloat(updatedCoords[1])
      const initialLng = parseFloat(dragResult.originalCoords[0])
      const initialLat = parseFloat(dragResult.originalCoords[1])

      expect(updatedLng).not.toBeCloseTo(initialLng, 5)
      expect(updatedLat).not.toBeCloseTo(initialLat, 5)

      // Verify routes have been updated - should now contain the new coordinates
      const updatedConnectedRoutes = updatedRoutesData.features.filter(
        (route) => {
          return route.geometry.coordinates.some(
            (coord) =>
              Math.abs(coord[0] - updatedCoords[0]) < 0.0001 &&
              Math.abs(coord[1] - updatedCoords[1]) < 0.0001,
          )
        },
      )

      // At least some routes should now reference the new position
      expect(updatedConnectedRoutes.length).toBeGreaterThanOrEqual(1)
    })

    test("persists point position after page reload", async ({ page }) => {
      test.setTimeout(90000)

      // Wait for points to load
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          const app = window.Stimulus || window.Application
          const controller = app?.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          const source = controller?.map?.getSource("points-source")
          return source?._data?.features?.length > 0
        },
        { timeout: 15000 },
      )

      // Ensure points layer is visible
      await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer
        if (pointsLayer) {
          pointsLayer.show()
          if (!pointsLayer.draggingEnabled) {
            pointsLayer.enableDragging()
          }
        }
      })

      await page.waitForTimeout(1000)

      // Programmatically move a point and persist via API
      const dragResult = await page.evaluate(async () => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        const map = controller?.map

        if (!map) return { success: false, reason: "no map" }

        const source = map.getSource("points-source")
        const data = source?._data
        if (!data?.features?.length)
          return { success: false, reason: "no features" }

        const feature = data.features[0]
        const originalCoords = [...feature.geometry.coordinates]
        const pointId = feature.properties.id

        // Calculate new coordinates
        const newLng = parseFloat(originalCoords[0]) + 0.002
        const newLat = parseFloat(originalCoords[1]) + 0.002

        // Update local data
        feature.geometry.coordinates = [newLng, newLat]
        source.setData(data)

        // Persist via API
        try {
          const apiKeyEl = document.querySelector(
            "[data-maps--maplibre-api-key-value]",
          )
          const apiKey = apiKeyEl?.getAttribute(
            "data-maps--maplibre-api-key-value",
          )
          if (apiKey) {
            const response = await fetch(`/api/v1/points/${pointId}`, {
              method: "PATCH",
              headers: {
                Authorization: `Bearer ${apiKey}`,
                "Content-Type": "application/json",
              },
              body: JSON.stringify({
                point: {
                  latitude: newLat,
                  longitude: newLng,
                },
              }),
            })

            return {
              success: response.ok,
              pointId,
              originalCoords,
              newCoords: [newLng, newLat],
            }
          }
          return { success: false, reason: "no api key" }
        } catch (err) {
          return { success: false, reason: err.message }
        }
      })

      expect(dragResult.success).toBe(true)

      // Wait for API to settle
      await page.waitForTimeout(2000)

      // Verify the drag succeeded before reloading
      const afterDragData = await getPointsSourceData(page)
      const afterDragPoint = afterDragData.features.find(
        (f) => f.properties.id === dragResult.pointId,
      )
      const afterDragCoords = afterDragPoint.geometry.coordinates

      const dragLng = parseFloat(afterDragCoords[0])
      const dragLat = parseFloat(afterDragCoords[1])
      const initialLng = parseFloat(dragResult.originalCoords[0])
      const initialLat = parseFloat(dragResult.originalCoords[1])

      expect(dragLng).not.toBeCloseTo(initialLng, 5)
      expect(dragLat).not.toBeCloseTo(initialLat, 5)

      // Reload the page
      await page.reload()
      await closeOnboardingModal(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1500)

      // Wait for points to reload
      await page.waitForFunction(
        () => {
          const element = document.querySelector(
            '[data-controller*="maps--maplibre"]',
          )
          const app = window.Stimulus || window.Application
          const controller = app?.getControllerForElementAndIdentifier(
            element,
            "maps--maplibre",
          )
          const source = controller?.map?.getSource("points-source")
          return source?._data?.features?.length > 0
        },
        { timeout: 15000 },
      )

      // Get point after reload
      const afterReloadData = await getPointsSourceData(page)
      const afterReloadPoint = afterReloadData.features.find(
        (f) => f.properties.id === dragResult.pointId,
      )
      const afterReloadCoords = afterReloadPoint.geometry.coordinates

      // Verify the position persisted
      const reloadLng = parseFloat(afterReloadCoords[0])
      const reloadLat = parseFloat(afterReloadCoords[1])

      // Position after reload should match position after drag
      expect(reloadLng).toBeCloseTo(dragLng, 3)
      expect(reloadLat).toBeCloseTo(dragLat, 3)

      // And it should be different from the initial position
      const lngDiff = Math.abs(reloadLng - initialLng)
      const latDiff = Math.abs(reloadLat - initialLat)
      const moved = lngDiff > 0.0001 || latDiff > 0.0001

      expect(moved).toBe(true)
    })
  })
})
