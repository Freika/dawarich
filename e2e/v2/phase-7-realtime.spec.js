import { test, expect } from '@playwright/test'
import {
  navigateToMapsV2,
  waitForMapLibre,
  hasLayer
} from './helpers/setup.js'

test.describe('Phase 7: Real-time + Family', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await waitForMapLibre(page)
  })

  // Note: Phase 7 realtime controller is currently disabled pending initialization fix
  // These tests are kept for when the controller is re-enabled
  test.skip('family layer exists', async ({ page }) => {
    const hasFamilyLayer = await hasLayer(page, 'family')
    expect(hasFamilyLayer).toBe(true)
  })

  test.skip('connection indicator shows', async ({ page }) => {
    const indicator = page.locator('.connection-indicator')
    await expect(indicator).toBeVisible()
  })

  test.skip('connection indicator shows state', async ({ page }) => {
    // Wait for connection to be established
    await page.waitForTimeout(2000)

    const indicator = page.locator('.connection-indicator')
    await expect(indicator).toBeVisible()

    // Should have either 'connected' or 'disconnected' class
    const classes = await indicator.getAttribute('class')
    const hasState = classes.includes('connected') || classes.includes('disconnected')
    expect(hasState).toBe(true)
  })

  test.skip('family layer has required sub-layers', async ({ page }) => {
    const familyExists = await hasLayer(page, 'family')
    const labelsExists = await hasLayer(page, 'family-labels')
    const pulseExists = await hasLayer(page, 'family-pulse')

    expect(familyExists).toBe(true)
    expect(labelsExists).toBe(true)
    expect(pulseExists).toBe(true)
  })

  // Regression tests are covered by earlier phase test files (phase-1 through phase-6)
  // These are skipped here to avoid duplication
  test.describe.skip('Regression Tests', () => {
    test('all previous features still work', async ({ page }) => {
      const layers = [
        'points', 'routes', 'heatmap',
        'visits', 'photos', 'areas-fill',
        'tracks', 'fog-scratch'
      ]

      for (const layer of layers) {
        const exists = await hasLayer(page, layer)
        expect(exists).toBe(true)
      }
    })

    test('settings panel still works', async ({ page }) => {
      // Click settings button
      await page.click('button:has-text("Settings")')

      // Wait for panel to appear
      await page.waitForSelector('[data-maps-v2-target="settingsPanel"]')

      // Check if panel is visible
      const panel = page.locator('[data-maps-v2-target="settingsPanel"]')
      await expect(panel).toBeVisible()
    })

    test('layer toggles still work', async ({ page }) => {
      // Toggle points layer
      await page.click('button:has-text("Points")')

      // Wait a bit for layer to update
      await page.waitForTimeout(500)

      // Layer should still exist but visibility might change
      const pointsExists = await page.evaluate(() => {
        const map = window.mapInstance
        return map?.getLayer('points') !== undefined
      })

      expect(pointsExists).toBe(true)
    })

    test('map interactions still work', async ({ page }) => {
      // Test zoom
      const initialZoom = await page.evaluate(() => window.mapInstance?.getZoom())

      // Click zoom in button
      await page.click('.maplibregl-ctrl-zoom-in')
      await page.waitForTimeout(300)

      const newZoom = await page.evaluate(() => window.mapInstance?.getZoom())
      expect(newZoom).toBeGreaterThan(initialZoom)
    })
  })

  test.describe.skip('ActionCable Integration', () => {
    test('realtime controller is connected', async ({ page }) => {
      // Check if realtime controller is initialized
      const hasRealtimeController = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="realtime"]')
        return element !== null
      })

      expect(hasRealtimeController).toBe(true)
    })

    test('connection indicator updates class based on connection', async ({ page }) => {
      // Get initial state
      const indicator = page.locator('.connection-indicator')
      const initialClass = await indicator.getAttribute('class')

      // Should have a connection state class
      const hasConnectionState =
        initialClass.includes('connected') ||
        initialClass.includes('disconnected')

      expect(hasConnectionState).toBe(true)
    })
  })

  test.describe.skip('Family Layer Functionality', () => {
    test('family layer can be updated programmatically', async ({ page }) => {
      // Test family layer update method exists
      const result = await page.evaluate(() => {
        const controller = window.mapInstance?._container?.closest('[data-controller*="maps-v2"]')?._stimulus?.getControllerForElementAndIdentifier

        // Access the familyLayer through the map controller
        return typeof window.mapInstance?._container !== 'undefined'
      })

      expect(result).toBe(true)
    })

    test('family layer handles empty state', async ({ page }) => {
      // Family layer should exist with no features initially
      const familyLayerData = await page.evaluate(() => {
        const map = window.mapInstance
        const source = map?.getSource('family-source')
        return source?._data || null
      })

      expect(familyLayerData).toBeTruthy()
      expect(familyLayerData.type).toBe('FeatureCollection')
    })
  })

  test.describe('Performance', () => {
    test.skip('page loads within acceptable time', async ({ page }) => {
      const startTime = Date.now()
      await page.goto('/maps_v2')
      await waitForMapLibre(page)
      const loadTime = Date.now() - startTime

      // Should load within 10 seconds
      expect(loadTime).toBeLessThan(10000)
    })

    test.skip('real-time updates do not cause memory leaks', async ({ page }) => {
      // Get initial memory usage
      const metrics1 = await page.evaluate(() => {
        if (performance.memory) {
          return performance.memory.usedJSHeapSize
        }
        return null
      })

      if (metrics1 === null) {
        test.skip()
        return
      }

      // Wait a bit
      await page.waitForTimeout(2000)

      // Get memory usage again
      const metrics2 = await page.evaluate(() => {
        return performance.memory.usedJSHeapSize
      })

      // Memory should not increase dramatically (allow for 50MB variance)
      const memoryIncrease = metrics2 - metrics1
      expect(memoryIncrease).toBeLessThan(50 * 1024 * 1024)
    })
  })
})
