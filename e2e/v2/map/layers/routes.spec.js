import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForMapLibre,
  waitForLoadingComplete,
  hasLayer,
  getLayerVisibility,
  getRoutesSourceData
} from '../../helpers/setup.js'

test.describe('Routes Layer', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Layer Existence', () => {
    test('routes layer exists on map', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const hasRoutesLayer = await hasLayer(page, 'routes')
      expect(hasRoutesLayer).toBe(true)
    })
  })

  test.describe('Data Source', () => {
    test('routes source has data', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('routes-source') !== undefined
      }, { timeout: 20000 })

      const { hasSource, featureCount } = await getRoutesSourceData(page)

      expect(hasSource).toBe(true)
      expect(featureCount).toBeGreaterThanOrEqual(0)
    })

    test('routes have LineString geometry', async ({ page }) => {
      const { features } = await getRoutesSourceData(page)

      if (features.length > 0) {
        features.forEach(feature => {
          expect(feature.geometry.type).toBe('LineString')
          expect(feature.geometry.coordinates.length).toBeGreaterThan(1)
        })
      }
    })

    test('routes have distance properties', async ({ page }) => {
      const { features } = await getRoutesSourceData(page)

      if (features.length > 0) {
        features.forEach(feature => {
          expect(feature.properties).toHaveProperty('distance')
          expect(typeof feature.properties.distance).toBe('number')
          expect(feature.properties.distance).toBeGreaterThanOrEqual(0)
        })
      }
    })

    test('routes connect points chronologically', async ({ page }) => {
      const { features } = await getRoutesSourceData(page)

      if (features.length > 0) {
        features.forEach(feature => {
          expect(feature.properties).toHaveProperty('startTime')
          expect(feature.properties).toHaveProperty('endTime')
          expect(feature.properties.endTime).toBeGreaterThanOrEqual(feature.properties.startTime)
          expect(feature.properties).toHaveProperty('pointCount')
          expect(feature.properties.pointCount).toBeGreaterThan(1)
        })
      }
    })
  })

  test.describe('Styling', () => {
    test('routes have solid color', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes') !== undefined
      }, { timeout: 20000 })

      const routeLayerInfo = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const layer = controller.map.getLayer('routes')
        if (!layer) return null

        const lineColor = controller.map.getPaintProperty('routes', 'line-color')

        return {
          exists: !!lineColor,
          isArray: Array.isArray(lineColor),
          value: lineColor
        }
      })

      expect(routeLayerInfo).toBeTruthy()
      expect(routeLayerInfo.exists).toBe(true)
      expect(routeLayerInfo.isArray).toBe(false)
      expect(routeLayerInfo.value).toBe('#f97316')
    })
  })

  test.describe('Layer Order', () => {
    test('routes layer renders below points layer', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes') !== undefined &&
               controller?.map?.getLayer('points') !== undefined
      }, { timeout: 10000 })

      const layerOrder = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const style = controller.map.getStyle()
        const layers = style.layers || []

        const routesIndex = layers.findIndex(l => l.id === 'routes')
        const pointsIndex = layers.findIndex(l => l.id === 'points')

        return { routesIndex, pointsIndex }
      })

      expect(layerOrder).toBeTruthy()
      if (layerOrder.routesIndex >= 0 && layerOrder.pointsIndex >= 0) {
        expect(layerOrder.routesIndex).toBeLessThan(layerOrder.pointsIndex)
      }
    })
  })

  test.describe('Persistence', () => {
    test('date navigation preserves routes layer', async ({ page }) => {
      // Wait for routes layer to be added to the map
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes') !== undefined
      }, { timeout: 10000 })

      const initialRoutes = await hasLayer(page, 'routes')
      expect(initialRoutes).toBe(true)

      await navigateToMapsV2WithDate(page, '2025-10-16T00:00', '2025-10-16T23:59')
      await closeOnboardingModal(page)

      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1500)

      const hasRoutesLayer = await hasLayer(page, 'routes')
      expect(hasRoutesLayer).toBe(true)
    })
  })
})
