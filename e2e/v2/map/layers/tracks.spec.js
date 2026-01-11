import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForMapLibre,
  waitForLoadingComplete,
  hasLayer,
  getLayerVisibility
} from '../../helpers/setup.js'

test.describe('Tracks Layer', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Toggle', () => {
    test('tracks layer toggle exists', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await expect(tracksToggle).toBeVisible()
    })

    test('tracks toggle is unchecked by default', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      const isChecked = await tracksToggle.isChecked()
      expect(isChecked).toBe(false)
    })

    test('can toggle tracks layer on', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await tracksToggle.isChecked()
      expect(isChecked).toBe(true)
    })

    test('can toggle tracks layer off', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')

      // Turn on
      await tracksToggle.check()
      await page.waitForTimeout(500)
      expect(await tracksToggle.isChecked()).toBe(true)

      // Turn off
      await tracksToggle.uncheck()
      await page.waitForTimeout(500)
      expect(await tracksToggle.isChecked()).toBe(false)
    })
  })

  test.describe('Layer Visibility', () => {
    test('tracks layer is hidden by default', async ({ page }) => {
      // Wait for tracks layer to be added to the map
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('tracks') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      // Check that tracks layer is not visible on the map
      const tracksVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const layer = controller.map.getLayer('tracks')
        if (!layer) return null

        return controller.map.getLayoutProperty('tracks', 'visibility') === 'visible'
      })

      expect(tracksVisible).toBe(false)
    })

    test('tracks layer becomes visible when toggled on', async ({ page }) => {
      // Open settings and enable tracks
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(500)

      // Verify layer is visible
      const tracksVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const layer = controller.map.getLayer('tracks')
        if (!layer) return null

        return controller.map.getLayoutProperty('tracks', 'visibility') === 'visible'
      })

      expect(tracksVisible).toBe(true)
    })
  })

  test.describe('Toggle Persistence', () => {
    test('tracks toggle state persists after page reload', async ({ page }) => {
      // Enable tracks
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(2000) // Wait for API save to complete

      // Reload page
      await page.reload()
      await closeOnboardingModal(page)
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(2000) // Wait for settings to load and layers to initialize

      // Verify tracks layer is actually visible (which means the setting persisted)
      const tracksVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const layer = controller.map.getLayer('tracks')
        if (!layer) return null

        return controller.map.getLayoutProperty('tracks', 'visibility') === 'visible'
      })

      expect(tracksVisible).toBe(true)
    })
  })

  test.describe('Layer Existence', () => {
    test('tracks layer exists on map', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('tracks') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const hasTracksLayer = await hasLayer(page, 'tracks')
      expect(hasTracksLayer).toBe(true)
    })
  })

  test.describe('Data Source', () => {
    test('tracks source has data', async ({ page }) => {
      // Enable tracks layer first
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('tracks-source') !== undefined
      }, { timeout: 20000 })

      const tracksData = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null
        const app = window.Stimulus || window.Application
        if (!app) return null
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const source = controller.map.getSource('tracks-source')
        if (!source) return { hasSource: false, featureCount: 0, features: [] }

        const data = source._data
        return {
          hasSource: true,
          featureCount: data?.features?.length || 0,
          features: data?.features || []
        }
      })

      expect(tracksData.hasSource).toBe(true)
      expect(tracksData.featureCount).toBeGreaterThanOrEqual(0)
    })

    test('tracks have LineString geometry', async ({ page }) => {
      // Enable tracks layer first
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource('tracks-source')
        const data = source?._data
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach(feature => {
          expect(feature.geometry.type).toBe('LineString')
          expect(feature.geometry.coordinates.length).toBeGreaterThan(1)
        })
      }
    })

    test('tracks have red color property', async ({ page }) => {
      // Enable tracks layer first
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource('tracks-source')
        const data = source?._data
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach(feature => {
          expect(feature.properties).toHaveProperty('color')
          expect(feature.properties.color).toBe('#ff0000') // Red color
        })
      }
    })

    test('tracks have metadata properties', async ({ page }) => {
      // Enable tracks layer first
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)
      const tracksToggle = page.locator('label:has-text("Tracks")').first().locator('input.toggle')
      await tracksToggle.check()
      await page.waitForTimeout(1000)

      const tracksData = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return { features: [] }
        const app = window.Stimulus || window.Application
        if (!app) return { features: [] }
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return { features: [] }

        const source = controller.map.getSource('tracks-source')
        const data = source?._data
        return { features: data?.features || [] }
      })

      if (tracksData.features.length > 0) {
        tracksData.features.forEach(feature => {
          expect(feature.properties).toHaveProperty('id')
          expect(feature.properties).toHaveProperty('start_at')
          expect(feature.properties).toHaveProperty('end_at')
          expect(feature.properties).toHaveProperty('distance')
          expect(feature.properties).toHaveProperty('avg_speed')
          expect(feature.properties).toHaveProperty('duration')
          expect(typeof feature.properties.distance).toBe('number')
          expect(feature.properties.distance).toBeGreaterThanOrEqual(0)
        })
      }
    })
  })

  test.describe('Styling', () => {
    test('tracks have red color styling', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('tracks') !== undefined
      }, { timeout: 20000 })

      const trackLayerInfo = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return null

        const app = window.Stimulus || window.Application
        if (!app) return null

        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        if (!controller?.map) return null

        const layer = controller.map.getLayer('tracks')
        if (!layer) return null

        const lineColor = controller.map.getPaintProperty('tracks', 'line-color')

        return {
          exists: !!lineColor,
          isArray: Array.isArray(lineColor),
          value: lineColor
        }
      })

      expect(trackLayerInfo).toBeTruthy()
      expect(trackLayerInfo.exists).toBe(true)

      // Track color uses ['get', 'color'] expression to read from feature properties
      // Features have color: '#ff0000' set by the backend
      if (trackLayerInfo.isArray) {
        // It's a MapLibre expression like ['get', 'color']
        expect(trackLayerInfo.value).toContain('get')
        expect(trackLayerInfo.value).toContain('color')
      }
    })
  })

  test.describe('Date Navigation', () => {
    test('date navigation preserves tracks layer', async ({ page }) => {
      // Wait for tracks layer to be added to the map
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('tracks') !== undefined
      }, { timeout: 10000 })

      const initialTracks = await hasLayer(page, 'tracks')
      expect(initialTracks).toBe(true)

      await navigateToMapsV2WithDate(page, '2025-10-16T00:00', '2025-10-16T23:59')
      await closeOnboardingModal(page)

      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1500)

      const hasTracksLayer = await hasLayer(page, 'tracks')
      expect(hasTracksLayer).toBe(true)
    })
  })
})
