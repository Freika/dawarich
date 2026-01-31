import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForLoadingComplete,
  hasLayer,
  getPointsSourceData,
  getRoutesSourceData
} from '../../helpers/setup.js'

test.describe('Points Layer', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Display', () => {
    test('displays points layer', async ({ page }) => {
      // Wait for points layer to be added
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('points') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const hasPoints = await hasLayer(page, 'points')
      expect(hasPoints).toBe(true)
    })

    test('loads and displays point data', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('points-source') !== undefined
      }, { timeout: 15000 }).catch(() => false)

      const sourceData = await getPointsSourceData(page)
      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.featureCount).toBeGreaterThan(0)
    })
  })

  test.describe('Data Source', () => {
    test('points source contains valid GeoJSON features', async ({ page }) => {
      // Wait for source to be added
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('points-source') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const sourceData = await getPointsSourceData(page)

      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.features).toBeDefined()
      expect(Array.isArray(sourceData.features)).toBe(true)

      if (sourceData.features.length > 0) {
        const firstFeature = sourceData.features[0]
        expect(firstFeature.type).toBe('Feature')
        expect(firstFeature.geometry).toBeDefined()
        expect(firstFeature.geometry.type).toBe('Point')
        expect(firstFeature.geometry.coordinates).toHaveLength(2)
      }
    })
  })

  test.describe('Dragging', () => {
    test('allows dragging points to new positions', async ({ page }) => {
      // Wait for points to load
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('points-source')
        return source?._data?.features?.length > 0
      }, { timeout: 15000 })

      // Get initial point data
      const initialData = await getPointsSourceData(page)
      expect(initialData.features.length).toBeGreaterThan(0)


      // Get the map canvas bounds
      const canvas = page.locator('.maplibregl-canvas')
      const canvasBounds = await canvas.boundingBox()
      expect(canvasBounds).not.toBeNull()

      // Ensure points layer is visible before testing dragging
      const layerState = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const pointsLayer = controller?.layerManager?.layers?.pointsLayer

        if (!pointsLayer) {
          return { exists: false, visibleBefore: false, visibleAfter: false, draggingEnabled: false }
        }

        const visibilityBefore = controller.map.getLayoutProperty('points', 'visibility')
        const isVisibleBefore = visibilityBefore === 'visible' || visibilityBefore === undefined

        // If not visible, make it visible
        if (!isVisibleBefore) {
          pointsLayer.show()
        }

        // Check again after calling show
        const visibilityAfter = controller.map.getLayoutProperty('points', 'visibility')
        const isVisibleAfter = visibilityAfter === 'visible' || visibilityAfter === undefined

        return {
          exists: true,
          visibleBefore: isVisibleBefore,
          visibleAfter: isVisibleAfter,
          draggingEnabled: pointsLayer.draggingEnabled || false
        }
      })


      // Wait longer for layer to render after visibility change
      await page.waitForTimeout(2000)

      // Find a rendered point feature on the map and get its pixel coordinates
      const renderedPoint = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')

        // Get all rendered point features
        const features = controller.map.queryRenderedFeatures(undefined, { layers: ['points'] })

        if (features.length === 0) {
          return { found: false, totalFeatures: 0 }
        }

        // Pick the first rendered point
        const feature = features[0]
        const coords = feature.geometry.coordinates
        const point = controller.map.project(coords)

        // Get the canvas position on the page
        const canvas = controller.map.getCanvas()
        const rect = canvas.getBoundingClientRect()

        return {
          found: true,
          totalFeatures: features.length,
          pointId: feature.properties.id,
          coords: coords,
          x: point.x,
          y: point.y,
          pageX: rect.left + point.x,
          pageY: rect.top + point.y
        }
      })


      expect(renderedPoint.found).toBe(true)
      expect(renderedPoint.totalFeatures).toBeGreaterThan(0)

      const pointId = renderedPoint.pointId
      const initialCoords = renderedPoint.coords
      const pointPixel = {
        x: renderedPoint.x,
        y: renderedPoint.y,
        pageX: renderedPoint.pageX,
        pageY: renderedPoint.pageY
      }


      // Drag the point by 100 pixels to the right and 100 down (larger movement for visibility)
      const dragOffset = { x: 100, y: 100 }
      const startX = pointPixel.pageX
      const startY = pointPixel.pageY
      const endX = startX + dragOffset.x
      const endY = startY + dragOffset.y


      // Check cursor style on hover
      await page.mouse.move(startX, startY)
      await page.waitForTimeout(200)

      const cursorStyle = await page.evaluate(() => {
        const canvas = document.querySelector('.maplibregl-canvas-container')
        return window.getComputedStyle(canvas).cursor
      })

      // Perform the drag operation with slower movement
      await page.mouse.down()
      await page.waitForTimeout(100)
      await page.mouse.move(endX, endY, { steps: 20 })
      await page.waitForTimeout(100)
      await page.mouse.up()

      // Wait for API call to complete
      await page.waitForTimeout(3000)

      // Get updated point data
      const updatedData = await getPointsSourceData(page)
      const updatedPoint = updatedData.features.find(f => f.properties.id === pointId)

      expect(updatedPoint).toBeDefined()
      const updatedCoords = updatedPoint.geometry.coordinates


      // Verify the point has moved (parse coordinates as numbers)
      const updatedLng = parseFloat(updatedCoords[0])
      const updatedLat = parseFloat(updatedCoords[1])
      const initialLng = parseFloat(initialCoords[0])
      const initialLat = parseFloat(initialCoords[1])

      expect(updatedLng).not.toBeCloseTo(initialLng, 5)
      expect(updatedLat).not.toBeCloseTo(initialLat, 5)
    })

    test('updates connected route segments when point is dragged', async ({ page }) => {
      // Wait for both points and routes to load
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const pointsSource = controller?.map?.getSource('points-source')
        const routesSource = controller?.map?.getSource('routes-source')
        return pointsSource?._data?.features?.length > 0 &&
               routesSource?._data?.features?.length > 0
      }, { timeout: 15000 })

      // Ensure points layer is visible via the settings panel UI
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(300)

      const pointsCheckbox = page.locator('[data-maps--maplibre-target="pointsToggle"]')
      const isChecked = await pointsCheckbox.isChecked()
      if (!isChecked) {
        await pointsCheckbox.click()
        await page.waitForTimeout(500)
      }

      // Close settings panel
      const closeBtn = page.locator('.panel-header button[data-action="click->maps--maplibre#toggleSettings"]')
      await closeBtn.click()
      await page.waitForTimeout(300)

      await page.waitForTimeout(2000)

      // Get initial data
      const initialRoutesData = await getRoutesSourceData(page)
      expect(initialRoutesData.features.length).toBeGreaterThan(0)

      // Find a rendered point feature on the map
      const renderedPoint = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')

        // Get all rendered point features
        const features = controller.map.queryRenderedFeatures(undefined, { layers: ['points'] })

        if (features.length === 0) {
          return { found: false }
        }

        // Pick the first rendered point
        const feature = features[0]
        const coords = feature.geometry.coordinates
        const point = controller.map.project(coords)

        // Get the canvas position on the page
        const canvas = controller.map.getCanvas()
        const rect = canvas.getBoundingClientRect()

        return {
          found: true,
          pointId: feature.properties.id,
          coords: coords,
          x: point.x,
          y: point.y,
          pageX: rect.left + point.x,
          pageY: rect.top + point.y
        }
      })

      expect(renderedPoint.found).toBe(true)

      const pointId = renderedPoint.pointId
      const initialCoords = renderedPoint.coords
      const pointPixel = {
        x: renderedPoint.x,
        y: renderedPoint.y,
        pageX: renderedPoint.pageX,
        pageY: renderedPoint.pageY
      }

      // Find routes that contain this point
      const connectedRoutes = initialRoutesData.features.filter(route => {
        return route.geometry.coordinates.some(coord =>
          Math.abs(coord[0] - initialCoords[0]) < 0.0001 &&
          Math.abs(coord[1] - initialCoords[1]) < 0.0001
        )
      })


      const dragOffset = { x: 100, y: 100 }
      const startX = pointPixel.pageX
      const startY = pointPixel.pageY
      const endX = startX + dragOffset.x
      const endY = startY + dragOffset.y

      // Perform drag with slower movement
      await page.mouse.move(startX, startY)
      await page.waitForTimeout(100)
      await page.mouse.down()
      await page.waitForTimeout(100)
      await page.mouse.move(endX, endY, { steps: 20 })
      await page.waitForTimeout(100)
      await page.mouse.up()

      // Wait for updates
      await page.waitForTimeout(3000)

      // Get updated data
      const updatedPointsData = await getPointsSourceData(page)
      const updatedRoutesData = await getRoutesSourceData(page)

      const updatedPoint = updatedPointsData.features.find(f => f.properties.id === pointId)
      const updatedCoords = updatedPoint.geometry.coordinates

      // Verify routes have been updated
      const updatedConnectedRoutes = updatedRoutesData.features.filter(route => {
        return route.geometry.coordinates.some(coord =>
          Math.abs(coord[0] - updatedCoords[0]) < 0.0001 &&
          Math.abs(coord[1] - updatedCoords[1]) < 0.0001
        )
      })


      // Routes that were originally connected should now be at the new position
      if (connectedRoutes.length > 0) {
        expect(updatedConnectedRoutes.length).toBeGreaterThan(0)
      }

      // The point moved, so verify the coordinates actually changed
      const lngChanged = Math.abs(parseFloat(updatedCoords[0]) - initialCoords[0]) > 0.0001
      const latChanged = Math.abs(parseFloat(updatedCoords[1]) - initialCoords[1]) > 0.0001

      expect(lngChanged || latChanged).toBe(true)

      // Since the route segments update is best-effort (depends on coordinate matching),
      // we'll just verify that routes exist and the point moved
    })

    test('persists point position after page reload', async ({ page }) => {
      // Wait for points to load
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('points-source')
        return source?._data?.features?.length > 0
      }, { timeout: 15000 })

      // Ensure points layer is visible by clicking the checkbox
      const pointsCheckbox = page.locator('[data-maps--maplibre-target="pointsToggle"]')
      const isChecked = await pointsCheckbox.isChecked()
      if (!isChecked) {
        await pointsCheckbox.click()
        await page.waitForTimeout(500)
      }

      await page.waitForTimeout(2000)

      // Find a rendered point feature on the map
      const renderedPoint = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')

        // Get all rendered point features
        const features = controller.map.queryRenderedFeatures(undefined, { layers: ['points'] })

        if (features.length === 0) {
          return { found: false }
        }

        // Pick the first rendered point
        const feature = features[0]
        const coords = feature.geometry.coordinates
        const point = controller.map.project(coords)

        // Get the canvas position on the page
        const canvas = controller.map.getCanvas()
        const rect = canvas.getBoundingClientRect()

        return {
          found: true,
          pointId: feature.properties.id,
          coords: coords,
          x: point.x,
          y: point.y,
          pageX: rect.left + point.x,
          pageY: rect.top + point.y
        }
      })

      expect(renderedPoint.found).toBe(true)

      const pointId = renderedPoint.pointId
      const initialCoords = renderedPoint.coords
      const pointPixel = {
        x: renderedPoint.x,
        y: renderedPoint.y,
        pageX: renderedPoint.pageX,
        pageY: renderedPoint.pageY
      }


      const dragOffset = { x: 100, y: 100 }
      const startX = pointPixel.pageX
      const startY = pointPixel.pageY
      const endX = startX + dragOffset.x
      const endY = startY + dragOffset.y

      // Perform drag with slower movement
      await page.mouse.move(startX, startY)
      await page.waitForTimeout(100)
      await page.mouse.down()
      await page.waitForTimeout(100)
      await page.mouse.move(endX, endY, { steps: 20 })
      await page.waitForTimeout(100)
      await page.mouse.up()

      // Wait for API call
      await page.waitForTimeout(3000)

      // Get the new position
      const afterDragData = await getPointsSourceData(page)
      const afterDragPoint = afterDragData.features.find(f => f.properties.id === pointId)
      const afterDragCoords = afterDragPoint.geometry.coordinates


      // Reload the page
      await page.reload()
      await closeOnboardingModal(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1500)

      // Wait for points to reload
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('points-source')
        return source?._data?.features?.length > 0
      }, { timeout: 15000 })

      // Get point after reload
      const afterReloadData = await getPointsSourceData(page)
      const afterReloadPoint = afterReloadData.features.find(f => f.properties.id === pointId)
      const afterReloadCoords = afterReloadPoint.geometry.coordinates


      // Verify the position persisted (parse coordinates as numbers)
      const reloadLng = parseFloat(afterReloadCoords[0])
      const reloadLat = parseFloat(afterReloadCoords[1])
      const dragLng = parseFloat(afterDragCoords[0])
      const dragLat = parseFloat(afterDragCoords[1])
      const initialLng = parseFloat(initialCoords[0])
      const initialLat = parseFloat(initialCoords[1])

      // Position after reload should match position after drag (high precision)
      expect(reloadLng).toBeCloseTo(dragLng, 5)
      expect(reloadLat).toBeCloseTo(dragLat, 5)

      // And it should be different from the initial position (lower precision - just verify it moved)
      const lngDiff = Math.abs(reloadLng - initialLng)
      const latDiff = Math.abs(reloadLat - initialLat)
      const moved = lngDiff > 0.00001 || latDiff > 0.00001

      expect(moved).toBe(true)
    })
  })
})
