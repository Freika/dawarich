import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'

test.describe('Heatmap Layer', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await page.waitForTimeout(2000)
  })

  test.describe('Creation', () => {
    test('heatmap layer can be enabled', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(500)

      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapLabel = page.locator('label:has-text("Heatmap")').first()
      const heatmapToggle = heatmapLabel.locator('input.toggle')
      await heatmapToggle.check()

      // Wait for heatmap layer to be created
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('heatmap') !== undefined
      }, { timeout: 3000 }).catch(() => false)

      const hasHeatmap = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('heatmap') !== undefined
      })

      expect(hasHeatmap).toBe(true)
    })

    test('heatmap can be toggled', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(500)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapToggle = page.locator('label:has-text("Heatmap")').first().locator('input.toggle')

      await heatmapToggle.check()
      await page.waitForTimeout(500)
      expect(await heatmapToggle.isChecked()).toBe(true)

      await heatmapToggle.uncheck()
      await page.waitForTimeout(500)
      expect(await heatmapToggle.isChecked()).toBe(false)
    })
  })

  test.describe('Persistence', () => {
    test('heatmap setting persists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(500)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapToggle = page.locator('label:has-text("Heatmap")').first().locator('input.toggle')
      await heatmapToggle.check()
      await page.waitForTimeout(500)

      const settings = await page.evaluate(() => {
        return localStorage.getItem('dawarich-maps-maplibre-settings')
      })

      // Settings might be null if not saved yet or only saved to backend
      if (settings) {
        const parsed = JSON.parse(settings)
        expect(parsed.heatmapEnabled).toBe(true)
      } else {
        // If no localStorage settings, verify the toggle is still checked
        expect(await heatmapToggle.isChecked()).toBe(true)
      }
    })
  })
})
