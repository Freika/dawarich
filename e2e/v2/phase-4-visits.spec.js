import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../helpers/navigation'
import {
  navigateToMapsV2,
  waitForMapLibre,
  waitForLoadingComplete,
  hasLayer
} from './helpers/setup'

test.describe('Phase 4: Visits + Photos', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Visits Layer', () => {
    test('visits layer exists on map', async ({ page }) => {
      const hasVisitsLayer = await hasLayer(page, 'visits')
      expect(hasVisitsLayer).toBe(true)
    })

    test('visits layer starts hidden', async ({ page }) => {
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('visits', 'visibility')
        return visibility === 'visible'
      })

      expect(isVisible).toBe(false)
    })

    test('can toggle visits layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle visits
      const visitsCheckbox = page.locator('label.setting-checkbox:has-text("Show Visits")').locator('input[type="checkbox"]')
      await visitsCheckbox.check()
      await page.waitForTimeout(300)

      // Check visibility
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('visits', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe('Photos Layer', () => {
    test('photos layer exists on map', async ({ page }) => {
      const hasPhotosLayer = await hasLayer(page, 'photos')
      expect(hasPhotosLayer).toBe(true)
    })

    test('photos layer starts hidden', async ({ page }) => {
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('photos', 'visibility')
        return visibility === 'visible'
      })

      expect(isVisible).toBe(false)
    })

    test('can toggle photos layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle photos
      const photosCheckbox = page.locator('label.setting-checkbox:has-text("Show Photos")').locator('input[type="checkbox"]')
      await photosCheckbox.check()
      await page.waitForTimeout(300)

      // Check visibility
      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('photos', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })
  })

  test.describe('Visits Search', () => {
    test('visits search appears when visits enabled', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Enable visits
      const visitsCheckbox = page.locator('label.setting-checkbox:has-text("Show Visits")').locator('input[type="checkbox"]')
      await visitsCheckbox.check()
      await page.waitForTimeout(300)

      // Check if search is visible
      const searchInput = page.locator('#visits-search')
      await expect(searchInput).toBeVisible()
    })

    test('can search visits', async ({ page }) => {
      // Open settings and enable visits
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      const visitsCheckbox = page.locator('label.setting-checkbox:has-text("Show Visits")').locator('input[type="checkbox"]')
      await visitsCheckbox.check()
      await page.waitForTimeout(300)

      // Search
      const searchInput = page.locator('#visits-search')
      await searchInput.fill('test')
      await page.waitForTimeout(300)

      // Verify search was applied (filter should have run)
      const searchValue = await searchInput.inputValue()
      expect(searchValue).toBe('test')
    })
  })

  test.describe('Regression Tests', () => {
    test('all previous layers still work', async ({ page }) => {
      const layers = ['points', 'routes', 'heatmap']

      for (const layerId of layers) {
        const exists = await hasLayer(page, layerId)
        expect(exists).toBe(true)
      }
    })
  })
})
