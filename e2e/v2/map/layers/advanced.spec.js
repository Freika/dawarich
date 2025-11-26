import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'

test.describe('Advanced Layers', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps_v2')
    await page.evaluate(() => {
      localStorage.removeItem('dawarich-maps-v2-settings')
    })

    await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await page.waitForTimeout(2000)
  })

  test.describe('Fog of War', () => {
    test('fog layer is disabled by default', async ({ page }) => {
      const fogEnabled = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('dawarich-maps-v2-settings') || '{}')
        return settings.fogEnabled
      })

      expect(fogEnabled).toBeFalsy()
    })

    test('can toggle fog layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const fogToggle = page.locator('label:has-text("Fog of War")').first().locator('input.toggle')
      await fogToggle.check()
      await page.waitForTimeout(500)

      expect(await fogToggle.isChecked()).toBe(true)
    })
  })

  test.describe('Scratch Map', () => {
    test('can toggle scratch map layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const scratchToggle = page.locator('label:has-text("Scratch map")').first().locator('input.toggle')
      await scratchToggle.check()
      await page.waitForTimeout(500)

      expect(await scratchToggle.isChecked()).toBe(true)
    })
  })
})
