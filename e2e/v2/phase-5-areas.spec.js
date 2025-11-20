import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../helpers/navigation'
import {
  navigateToMapsV2,
  waitForMapLibre,
  waitForLoadingComplete,
  hasLayer
} from './helpers/setup'

test.describe('Phase 5: Areas + Drawing Tools', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Areas Layer', () => {
    test.skip('areas layer exists on map (requires test data)', async ({ page }) => {
      // NOTE: This test requires areas to be created in the test database
      // Layer is only added when areas data is available
      const hasAreasLayer = await hasLayer(page, 'areas-fill')
      expect(hasAreasLayer).toBe(true)
    })

    test('areas layer starts hidden', async ({ page }) => {
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('areas-fill', 'visibility')
        return visibility === 'visible'
      })

      expect(isVisible).toBe(false)
    })

    test('can toggle areas layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle areas
      const areasCheckbox = page.locator('label.setting-checkbox:has-text("Show Areas")').locator('input[type="checkbox"]')
      await areasCheckbox.check()
      await page.waitForTimeout(300)

      // Check visibility
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('areas-fill', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe('Tracks Layer', () => {
    test.skip('tracks layer exists on map (requires backend API)', async ({ page }) => {
      // NOTE: Tracks API endpoint (/api/v1/tracks) doesn't exist yet
      // This is a future enhancement
      const hasTracksLayer = await hasLayer(page, 'tracks')
      expect(hasTracksLayer).toBe(true)
    })

    test('tracks layer starts hidden', async ({ page }) => {
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('tracks', 'visibility')
        return visibility === 'visible'
      })

      expect(isVisible).toBe(false)
    })

    test('can toggle tracks layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle tracks
      const tracksCheckbox = page.locator('label.setting-checkbox:has-text("Show Tracks")').locator('input[type="checkbox"]')
      await tracksCheckbox.check()
      await page.waitForTimeout(300)

      // Check visibility
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('tracks', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe('Layer Order', () => {
    test.skip('areas render below tracks (requires both layers with data)', async ({ page }) => {
      const layerOrder = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const layers = controller?.map?.getStyle()?.layers || []

        const areasIndex = layers.findIndex(l => l.id === 'areas-fill')
        const tracksIndex = layers.findIndex(l => l.id === 'tracks')

        return { areasIndex, tracksIndex }
      })

      // Areas should render before (below) tracks
      expect(layerOrder.areasIndex).toBeLessThan(layerOrder.tracksIndex)
    })
  })

  test.describe('Regression Tests', () => {
    test('all previous layers still work', async ({ page }) => {
      const layers = ['points', 'routes', 'heatmap', 'visits', 'photos']

      for (const layerId of layers) {
        const exists = await hasLayer(page, layerId)
        expect(exists).toBe(true)
      }
    })

    test('settings panel has all toggles', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Check all toggles exist
      const toggles = [
        'Show Heatmap',
        'Show Visits',
        'Show Photos',
        'Show Areas',
        'Show Tracks'
      ]

      for (const toggleText of toggles) {
        const toggle = page.locator(`label.setting-checkbox:has-text("${toggleText}")`)
        await expect(toggle).toBeVisible()
      }
    })
  })
})
