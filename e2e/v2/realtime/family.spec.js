import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js'

test.describe('Realtime Family Tracking', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
  })

  test.describe('Family Layer', () => {
    test.skip('family layer exists but is hidden by default', async ({ page }) => {
      // Family layer is created but hidden until ActionCable data arrives
      const layerExists = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('family') !== undefined
      })

      // Test requires family setup
      expect(layerExists).toBe(true)
    })
  })

  test.describe('ActionCable Connection', () => {
    test.skip('establishes ActionCable connection for family tracking', async ({ page }) => {
      // This test requires ActionCable setup and family configuration
      // Skip for now as it needs backend family data
    })
  })
})
