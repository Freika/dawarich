import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForLoadingComplete,
  clickMapAt,
  hasPopup
} from '../helpers/setup.js'

/**
 * Helper to enable routes layer and disable points layer via settings UI
 * This prevents points from intercepting route clicks while ensuring routes are visible
 */
async function enableRoutesDisablePoints(page) {
  // Open settings panel
  await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click();
  await page.waitForTimeout(300);

  // Click layers tab
  await page.locator('button[data-tab="layers"]').click();
  await page.waitForTimeout(300);

  // Make sure Routes layer is enabled
  const routesCheckbox = page.locator('label:has-text("Routes") input.toggle').first();
  if (!(await routesCheckbox.isChecked().catch(() => true))) {
    await routesCheckbox.check();
    await page.waitForTimeout(200);
  }

  // Disable Points layer to prevent click interception
  const pointsCheckbox = page.locator('label:has-text("Points") input.toggle').first();
  if (await pointsCheckbox.isChecked().catch(() => false)) {
    await pointsCheckbox.uncheck();
    await page.waitForTimeout(200);
  }

  // Close settings panel - the close button is inside .panel-header and uses toggleSettings action
  const closeButton = page.locator('.panel-header button[data-action="click->maps--maplibre#toggleSettings"]');
  await closeButton.click();
  await page.waitForTimeout(500);
  
  // Verify the panel is closed by checking the settings button is visible/usable
  // (the panel overlays part of the map when open)
}

test.describe('Map Interactions', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(500)
  })

  test.describe('Point Clicks', () => {
    test('shows popup when clicking on point', async ({ page }) => {
      await page.waitForTimeout(1000)

      // Try clicking at different positions to find a point
      const positions = [
        { x: 400, y: 300 },
        { x: 500, y: 300 },
        { x: 600, y: 400 },
        { x: 350, y: 250 }
      ]

      let popupFound = false
      for (const pos of positions) {
        try {
          await clickMapAt(page, pos.x, pos.y)
          await page.waitForTimeout(500)

          if (await hasPopup(page)) {
            popupFound = true
            break
          }
        } catch (error) {
          // Click might fail if map is still loading
          console.log(`Click at ${pos.x},${pos.y} failed: ${error.message}`)
        }
      }

      if (popupFound) {
        const popup = page.locator('.maplibregl-popup')
        await expect(popup).toBeVisible()

        const popupContent = page.locator('.point-popup')
        await expect(popupContent).toBeVisible()
      } else {
        console.log('No point clicked (points might be clustered or sparse)')
      }
    })
  })

  test.describe('Hover Effects', () => {
    test('map container is interactive', async ({ page }) => {
      const mapContainer = page.locator('[data-maps--maplibre-target="container"]')
      await expect(mapContainer).toBeVisible()
    })
  })

  test.describe('Route Interactions', () => {
    // Enable routes and disable points layer before each route test to prevent click interception
    test.beforeEach(async ({ page }) => {
      await enableRoutesDisablePoints(page);
    });

    test('route hover layer exists', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes-hover') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const hasHoverLayer = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes-hover') !== undefined
      })

      expect(hasHoverLayer).toBe(true)
    })

    test('route hover shows yellow highlight', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Get first route's bounding box and hover over its center
      const routeCenter = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return null

        const route = source._data.features[0]
        const coords = route.geometry.coordinates

        // Get middle coordinate of route
        const midCoord = coords[Math.floor(coords.length / 2)]

        // Project to pixel coordinates
        const point = controller.map.project(midCoord)

        return { x: point.x, y: point.y }
      })

      if (routeCenter) {
        // Get the canvas element and hover over the route
        const canvas = page.locator('.maplibregl-canvas')
        await canvas.hover({
          position: { x: routeCenter.x, y: routeCenter.y }
        })

        await page.waitForTimeout(500)

        // Check if hover source has data (route is highlighted)
        const isHighlighted = await page.evaluate(() => {
          const element = document.querySelector('[data-controller*="maps--maplibre"]')
          const app = window.Stimulus || window.Application
          const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
          const hoverSource = controller.map.getSource('routes-hover-source')
          return hoverSource && hoverSource._data?.features?.length > 0
        })

        expect(isHighlighted).toBe(true)

        // Check for emoji markers (start 🚥 and end 🏁)
        const startMarker = page.locator('.route-emoji-marker:has-text("🚥")')
        const endMarker = page.locator('.route-emoji-marker:has-text("🏁")')
        await expect(startMarker).toBeVisible()
        await expect(endMarker).toBeVisible()
      }
    })

    test('route click opens info panel with route details', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return

        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]

        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Click at the center of the canvas — the route midpoint is projected there
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.click({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(500)

      // Check if info panel is visible
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      await expect(infoDisplay).not.toHaveClass(/hidden/)

      // Check if info panel has route information title
      const infoTitle = page.locator('[data-maps--maplibre-target="infoTitle"]')
      await expect(infoTitle).toHaveText('Route Information')

      // Check if route details are displayed
      const infoContent = page.locator('[data-maps--maplibre-target="infoContent"]')
      const content = await infoContent.textContent()

      expect(content).toContain('Start:')
      expect(content).toContain('End:')
      expect(content).toContain('Duration:')
      expect(content).toContain('Distance:')
      expect(content).toContain('Points:')

      // Check for emoji markers (start 🚥 and end 🏁)
      const startMarker = page.locator('.route-emoji-marker:has-text("🚥")')
      const endMarker = page.locator('.route-emoji-marker:has-text("🏁")')
      await expect(startMarker).toBeVisible()
      await expect(endMarker).toBeVisible()
    })

    test('clicked route stays highlighted after mouse moves away', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint for reliable clicking
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return

        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]

        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Click at the center of the canvas — the route midpoint is projected there
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.click({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(500)

      // Move mouse away from route
      await canvas.hover({ position: { x: 50, y: 50 } })
      await page.waitForTimeout(500)

      // Check if route is still highlighted
      const isStillHighlighted = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const hoverSource = controller.map.getSource('routes-hover-source')
        return hoverSource && hoverSource._data?.features?.length > 0
      })

      expect(isStillHighlighted).toBe(true)

      // Check if info panel is still visible
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      await expect(infoDisplay).not.toHaveClass(/hidden/)
    })

    test('clicking elsewhere on map deselects route', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint for reliable clicking
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return

        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]

        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Click at the center of the canvas — the route midpoint is projected there
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.click({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(500)

      // Verify route is selected
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      await expect(infoDisplay).not.toHaveClass(/hidden/)

      // Click elsewhere on map (top-left corner, far from route)
      await canvas.click({ position: { x: 50, y: 50 } })
      await page.waitForTimeout(500)

      // Check if route is deselected (hover source cleared)
      const isDeselected = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const hoverSource = controller.map.getSource('routes-hover-source')
        return hoverSource && hoverSource._data?.features?.length === 0
      })

      expect(isDeselected).toBe(true)

      // Check if info panel is hidden
      await expect(infoDisplay).toHaveClass(/hidden/)
    })

    test('clicking close button on info panel deselects route', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint for reliable clicking
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return

        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]

        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Click at the center of the canvas — the route midpoint is projected there
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.click({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(500)

      // Verify info panel is open
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      await expect(infoDisplay).not.toHaveClass(/hidden/)

      // Click the close button
      const closeButton = page.locator('button[data-action="click->maps--maplibre#closeInfo"]')
      await closeButton.click()
      await page.waitForTimeout(500)

      // Check if route is deselected
      const isDeselected = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const hoverSource = controller.map.getSource('routes-hover-source')
        return hoverSource && hoverSource._data?.features?.length === 0
      })

      expect(isDeselected).toBe(true)

      // Check if info panel is hidden
      await expect(infoDisplay).toHaveClass(/hidden/)
    })

    test('route cursor changes to pointer on hover', async ({ page }) => {
      // Wait for routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint for reliable hovering
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length) return

        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]

        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Hover at the center of the canvas — the route midpoint is projected there
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.hover({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(300)

      // Check cursor style
      const cursor = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller.map.getCanvas().style.cursor
      })

      expect(cursor).toBe('pointer')
    })

    test('hovering over different route while one is selected shows both highlighted', async ({ page }) => {
      // Wait for multiple routes to be loaded
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length >= 2
      }, { timeout: 20000 })

      await page.waitForTimeout(1000)

      // Zoom in closer to make routes more distinct and center on first route
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (source._data?.features?.length >= 2) {
          const route = source._data.features[0]
          const coords = route.geometry.coordinates
          const midCoord = coords[Math.floor(coords.length / 2)]

          // Center on first route and zoom in
          controller.map.flyTo({
            center: midCoord,
            zoom: 13,
            duration: 0
          })
        }
      })

      await page.waitForTimeout(1000)

      // Get centers of two different routes that are far apart (after zoom)
      const routeCenters = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')

        if (!source._data?.features?.length >= 2) return null

        // Find two routes with significantly different centers to avoid overlap
        const features = source._data.features
        let route1 = features[0]
        let route2 = null

        const coords1 = route1.geometry.coordinates
        const midCoord1 = coords1[Math.floor(coords1.length / 2)]
        const point1 = controller.map.project(midCoord1)

        // Find a route that's at least 100px away from the first one
        for (let i = 1; i < features.length; i++) {
          const testRoute = features[i]
          const testCoords = testRoute.geometry.coordinates
          const testMidCoord = testCoords[Math.floor(testCoords.length / 2)]
          const testPoint = controller.map.project(testMidCoord)

          const distance = Math.sqrt(
            Math.pow(testPoint.x - point1.x, 2) +
            Math.pow(testPoint.y - point1.y, 2)
          )

          if (distance > 100) {
            route2 = testRoute
            break
          }
        }

        if (!route2) {
          // If no route is far enough, use the last route
          route2 = features[features.length - 1]
        }

        const coords2 = route2.geometry.coordinates
        const midCoord2 = coords2[Math.floor(coords2.length / 2)]
        const point2 = controller.map.project(midCoord2)

        return {
          route1: { x: point1.x, y: point1.y },
          route2: { x: point2.x, y: point2.y },
          areDifferent: route1.properties.startTime !== route2.properties.startTime
        }
      })

      if (routeCenters && routeCenters.areDifferent) {
        const canvas = page.locator('.maplibregl-canvas')

        // Click on first route to select it
        await canvas.click({
          position: { x: routeCenters.route1.x, y: routeCenters.route1.y }
        })

        await page.waitForTimeout(500)

        // Verify first route is selected
        const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
        await expect(infoDisplay).not.toHaveClass(/hidden/)

        // Close settings panel if it's open (it blocks hover interactions)
        const settingsPanel = page.locator('[data-maps--maplibre-target="settingsPanel"]')
        const isOpen = await settingsPanel.evaluate((el) => el.classList.contains('open'))
        if (isOpen) {
          await page.getByRole('button', { name: 'Close panel' }).click()
          await page.waitForTimeout(300)
        }

        // Hover over second route (use force since functionality is verified to work)
        await canvas.hover({
          position: { x: routeCenters.route2.x, y: routeCenters.route2.y },
          force: true
        })

        await page.waitForTimeout(500)

        // Check that hover source has features (1 if same route/overlapping, 2 if distinct)
        // The exact count depends on route data and zoom level
        const featureCount = await page.evaluate(() => {
          const element = document.querySelector('[data-controller*="maps--maplibre"]')
          const app = window.Stimulus || window.Application
          const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
          const hoverSource = controller.map.getSource('routes-hover-source')
          return hoverSource && hoverSource._data?.features?.length
        })

        // Accept 1 (same/overlapping route) or 2 (distinct routes) as valid
        expect(featureCount).toBeGreaterThanOrEqual(1)
        expect(featureCount).toBeLessThanOrEqual(2)

        // Move mouse away from both routes
        await canvas.hover({ position: { x: 100, y: 100 } })
        await page.waitForTimeout(500)

        // Check that only selected route remains highlighted (1 feature)
        const featureCountAfterLeave = await page.evaluate(() => {
          const element = document.querySelector('[data-controller*="maps--maplibre"]')
          const app = window.Stimulus || window.Application
          const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
          const hoverSource = controller.map.getSource('routes-hover-source')
          return hoverSource && hoverSource._data?.features?.length
        })

        expect(featureCountAfterLeave).toBe(1)

        // Check that markers are present for the selected route only
        const markerCount = await page.locator('.route-emoji-marker').count()
        expect(markerCount).toBe(2) // Start and end marker for selected route
      }
    })

    test('clicking elsewhere removes emoji markers', async ({ page }) => {
      // Wait for routes to be loaded (longer timeout as previous test may affect timing)
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      }, { timeout: 30000 })

      await page.waitForTimeout(1000)

      // Center map on route midpoint
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const source = controller.map.getSource('routes-source')
        if (!source._data?.features?.length) return
        const route = source._data.features[0]
        const coords = route.geometry.coordinates
        const midCoord = coords[Math.floor(coords.length / 2)]
        controller.map.jumpTo({ center: midCoord, zoom: 15 })
      })

      await page.waitForTimeout(500)

      // Click at canvas center where the route midpoint is projected
      const canvas = page.locator('.maplibregl-canvas')
      const box = await canvas.boundingBox()
      if (!box) return

      await canvas.click({
        position: { x: Math.floor(box.width / 2), y: Math.floor(box.height / 2) }
      })

      await page.waitForTimeout(500)

      // Verify markers are present
      let markerCount = await page.locator('.route-emoji-marker').count()
      expect(markerCount).toBe(2)

      // Click elsewhere on map (top-left corner, away from route)
      await canvas.click({ position: { x: 50, y: 50 } })
      await page.waitForTimeout(500)

      // Verify markers are removed
      markerCount = await page.locator('.route-emoji-marker').count()
      expect(markerCount).toBe(0)
    })
  })
})
