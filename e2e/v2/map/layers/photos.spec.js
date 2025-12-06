import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../../helpers/setup.js'

test.describe('Photos Layer', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Toggle', () => {
    test('photos layer toggle exists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const photosToggle = page.locator('label:has-text("Photos")').first().locator('input.toggle')
      await expect(photosToggle).toBeVisible()
    })

    test('can toggle photos layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const photosToggle = page.locator('label:has-text("Photos")').first().locator('input.toggle')
      await photosToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await photosToggle.isChecked()
      expect(isChecked).toBe(true)
    })
  })
})
