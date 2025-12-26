import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import {
  navigateToMapsV2,
  waitForMapLibre,
  getMapZoom
} from '../helpers/setup.js'

test.describe('Map Navigation', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
  })

  test.describe('Controls', () => {
    test('displays navigation controls', async ({ page }) => {
      await waitForMapLibre(page)

      const navControls = page.locator('.maplibregl-ctrl-top-right')
      await expect(navControls).toBeVisible()

      const zoomIn = page.locator('.maplibregl-ctrl-zoom-in')
      const zoomOut = page.locator('.maplibregl-ctrl-zoom-out')
      await expect(zoomIn).toBeVisible()
      await expect(zoomOut).toBeVisible()
    })

    test('zooms in when clicking zoom in button', async ({ page }) => {
      await waitForMapLibre(page)

      const initialZoom = await getMapZoom(page)
      await page.locator('.maplibregl-ctrl-zoom-in').click()
      await page.waitForTimeout(500)
      const newZoom = await getMapZoom(page)

      expect(newZoom).toBeGreaterThan(initialZoom)
    })

    test('zooms out when clicking zoom out button', async ({ page }) => {
      await waitForMapLibre(page)

      // First zoom in to ensure we can zoom out
      await page.locator('.maplibregl-ctrl-zoom-in').click()
      await page.waitForTimeout(500)

      const initialZoom = await getMapZoom(page)
      await page.locator('.maplibregl-ctrl-zoom-out').click()
      await page.waitForTimeout(500)
      const newZoom = await getMapZoom(page)

      expect(newZoom).toBeLessThan(initialZoom)
    })
  })

  test.describe('Date Picker', () => {
    test('displays date navigation inputs', async ({ page }) => {
      const startInput = page.locator('input[type="datetime-local"][name="start_at"]')
      const endInput = page.locator('input[type="datetime-local"][name="end_at"]')
      const searchButton = page.locator('input[type="submit"][value="Search"]')

      await expect(startInput).toBeVisible()
      await expect(endInput).toBeVisible()
      await expect(searchButton).toBeVisible()
    })
  })
})
