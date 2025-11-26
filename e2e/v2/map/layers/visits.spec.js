import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../../helpers/setup.js'

test.describe('Visits Layer', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Toggle', () => {
    test('visits layer toggle exists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const visitsToggle = page.locator('label:has-text("Visits")').first().locator('input.toggle')
      await expect(visitsToggle).toBeVisible()
    })

    test('can toggle visits layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const visitsToggle = page.locator('label:has-text("Visits")').first().locator('input.toggle')
      await visitsToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await visitsToggle.isChecked()
      expect(isChecked).toBe(true)
    })
  })
})
