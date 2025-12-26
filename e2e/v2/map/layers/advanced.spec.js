import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'

test.describe('Advanced Layers', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map/v2')
    await page.evaluate(() => {
      localStorage.removeItem('dawarich-maps-maplibre-settings')
    })

    await page.goto('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await page.waitForTimeout(2000)
  })

  test.describe('Fog of War', () => {
    test('fog layer toggle exists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const fogToggle = page.locator('label:has-text("Fog of War")').first().locator('input.toggle')
      await expect(fogToggle).toBeVisible()
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

    test('fog radius setting can be changed and applied', async ({ page }) => {
      // Enable fog layer first
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const fogToggle = page.locator('label:has-text("Fog of War")').first().locator('input.toggle')
      await fogToggle.check()
      await page.waitForTimeout(500)

      // Go to advanced settings tab
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      // Find fog radius slider
      const fogRadiusSlider = page.locator('input[name="fogOfWarRadius"]')
      await expect(fogRadiusSlider).toBeVisible()

      // Change the slider value using evaluate to trigger input event
      await fogRadiusSlider.evaluate((slider) => {
        slider.value = '500'
        slider.dispatchEvent(new Event('input', { bubbles: true }))
      })
      await page.waitForTimeout(200)

      // Verify display value updated
      const displayValue = page.locator('[data-maps--maplibre-target="fogRadiusValue"]')
      await expect(displayValue).toHaveText('500m')

      // Verify slider value was set
      expect(await fogRadiusSlider.inputValue()).toBe('500')

      // Click Apply Settings button
      const applyButton = page.locator('button:has-text("Apply Settings")')
      await applyButton.click()
      await page.waitForTimeout(500)

      // Verify no errors in console
      const consoleErrors = []
      page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text())
      })
      await page.waitForTimeout(500)
      expect(consoleErrors.filter(e => e.includes('fog_layer'))).toHaveLength(0)
    })

    test('fog settings can be applied without errors when fog layer is not visible', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      // Change fog radius slider without enabling fog layer
      const fogRadiusSlider = page.locator('input[name="fogOfWarRadius"]')
      await fogRadiusSlider.evaluate((slider) => {
        slider.value = '750'
        slider.dispatchEvent(new Event('input', { bubbles: true }))
      })
      await page.waitForTimeout(200)

      // Click Apply Settings - this should not throw an error
      const applyButton = page.locator('button:has-text("Apply Settings")')
      await applyButton.click()
      await page.waitForTimeout(500)

      // Verify no JavaScript errors occurred
      const consoleErrors = []
      page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text())
      })
      await page.waitForTimeout(500)
      expect(consoleErrors.filter(e => e.includes('undefined') || e.includes('fog'))).toHaveLength(0)
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
