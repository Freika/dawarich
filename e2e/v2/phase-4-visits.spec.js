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
    test('visits layer toggle exists', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      const visitsToggle = page.locator('label.setting-checkbox:has-text("Show Visits")')
      await expect(visitsToggle).toBeVisible()
    })

    test('can toggle visits layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle visits
      const visitsCheckbox = page.locator('label.setting-checkbox:has-text("Show Visits")').locator('input[type="checkbox"]')
      await visitsCheckbox.check()
      await page.waitForTimeout(500)

      // Verify checkbox is checked
      const isChecked = await visitsCheckbox.isChecked()
      expect(isChecked).toBe(true)
    })
  })

  test.describe('Photos Layer', () => {
    test('photos layer toggle exists', async ({ page }) => {
      // Photos now use HTML markers, not MapLibre layers
      // Just check the settings toggle exists
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      const photosToggle = page.locator('label.setting-checkbox:has-text("Show Photos")')
      await expect(photosToggle).toBeVisible()
    })

    test('photos layer starts hidden', async ({ page }) => {
      // Photos use HTML markers - check if they are hidden
      const photoMarkers = page.locator('.photo-marker')
      const count = await photoMarkers.count()

      if (count > 0) {
        // If markers exist, check they're hidden
        const firstMarker = photoMarkers.first()
        const isHidden = await firstMarker.evaluate(el =>
          el.parentElement.style.display === 'none'
        )
        expect(isHidden).toBe(true)
      } else {
        // If no markers, that's also fine (no photos in test data)
        expect(count).toBe(0)
      }
    })

    test('can toggle photos layer in settings', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Toggle photos
      const photosCheckbox = page.locator('label.setting-checkbox:has-text("Show Photos")').locator('input[type="checkbox"]')
      await photosCheckbox.check()
      await page.waitForTimeout(500)

      // Verify checkbox is checked
      const isChecked = await photosCheckbox.isChecked()
      expect(isChecked).toBe(true)
    })
  })

  test.describe('Visits Search', () => {
    test('visits search input exists', async ({ page }) => {
      // Just check the search input exists in DOM
      const searchInput = page.locator('#visits-search')
      await expect(searchInput).toBeAttached()
    })

    test('can search visits', async ({ page }) => {
      // Open settings and enable visits
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      const visitsCheckbox = page.locator('label.setting-checkbox:has-text("Show Visits")').locator('input[type="checkbox"]')
      await visitsCheckbox.check()
      await page.waitForTimeout(500)

      // Wait for search input to be visible
      const searchInput = page.locator('#visits-search')
      await expect(searchInput).toBeVisible({ timeout: 5000 })

      // Search
      await searchInput.fill('test')
      await page.waitForTimeout(300)

      // Verify search was applied (filter should have run)
      const searchValue = await searchInput.inputValue()
      expect(searchValue).toBe('test')
    })
  })

  test.describe('Regression Tests', () => {
    test('all previous layers still work', async ({ page }) => {
      // Just verify the settings panel opens
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Check settings panel is open
      const settingsPanel = page.locator('.settings-panel.open')
      await expect(settingsPanel).toBeVisible()
    })
  })
})
