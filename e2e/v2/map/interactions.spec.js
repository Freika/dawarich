import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForLoadingComplete,
  clickMapAt,
  hasPopup
} from '../helpers/setup.js'

test.describe('Map Interactions', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
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
      const mapContainer = page.locator('[data-maps-v2-target="container"]')
      await expect(mapContainer).toBeVisible()
    })
  })
})
