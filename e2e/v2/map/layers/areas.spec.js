import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../../helpers/setup.js'

test.describe('Areas Layer', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Toggle', () => {
    test('areas layer toggle exists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await expect(areasToggle).toBeVisible()
    })

    test('can toggle areas layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await areasToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await areasToggle.isChecked()
      expect(isChecked).toBe(true)
    })
  })
})
