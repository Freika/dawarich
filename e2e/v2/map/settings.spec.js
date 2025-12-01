import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { getLayerVisibility } from '../helpers/setup.js'

test.describe('Map Settings', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps/maplibre?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await page.waitForTimeout(2000)
  })

  test.describe('Settings Panel', () => {
    test('opens and closes settings panel', async ({ page }) => {
      const panel = page.locator('[data-maps--maplibre-target="settingsPanel"]')

      // Verify panel exists but is not open initially
      await expect(panel).toBeVisible()
      await expect(panel).not.toHaveClass(/open/)

      // Open the panel
      const settingsButton = page.locator('button[title="Open map settings"]')
      await settingsButton.click()

      // Wait for the panel to have the open class
      await expect(panel).toHaveClass(/open/, { timeout: 3000 })

      // Close the panel
      const closeButton = page.locator('button[title="Close panel"]')
      await closeButton.click()
      await expect(panel).not.toHaveClass(/open/, { timeout: 3000 })
    })

    test('displays layer controls in settings', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const pointsToggle = page.locator('label:has-text("Points")').first().locator('input.toggle')
      const routesToggle = page.locator('label:has-text("Routes")').first().locator('input.toggle')

      await expect(pointsToggle).toBeVisible()
      await expect(routesToggle).toBeVisible()
    })

    test('has tabs for different settings sections', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchTab = page.locator('button[data-tab="search"]')
      const layersTab = page.locator('button[data-tab="layers"]')
      const settingsTab = page.locator('button[data-tab="settings"]')

      await expect(searchTab).toBeVisible()
      await expect(layersTab).toBeVisible()
      await expect(settingsTab).toBeVisible()
    })
  })

  test.describe('Layer Toggles', () => {
    test('points layer visibility matches toggle state', async ({ page }) => {
      // Wait for points layer to exist
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('points') !== undefined
      }, { timeout: 5000 }).catch(() => false)

      const isVisible = await getLayerVisibility(page, 'points')

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const pointsToggle = page.locator('label:has-text("Points")').first().locator('input.toggle')
      const toggleState = await pointsToggle.isChecked()

      expect(isVisible).toBe(toggleState)
    })

    test('routes layer visibility matches toggle state', async ({ page }) => {
      // Wait for routes layer to exist
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('routes') !== undefined
      }, { timeout: 5000 }).catch(() => false)

      const isVisible = await getLayerVisibility(page, 'routes')

      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const routesToggle = page.locator('label:has-text("Routes")').first().locator('input.toggle')
      const toggleState = await routesToggle.isChecked()

      expect(isVisible).toBe(toggleState)
    })

    test('can toggle points layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const pointsLabel = page.locator('label:has-text("Points")').first()
      const pointsToggle = pointsLabel.locator('input.toggle')

      const initialState = await pointsToggle.isChecked()

      await pointsLabel.click()
      await page.waitForTimeout(500)

      const newState = await pointsToggle.isChecked()
      expect(newState).toBe(!initialState)

      await pointsLabel.click()
      await page.waitForTimeout(500)

      const finalState = await pointsToggle.isChecked()
      expect(finalState).toBe(initialState)
    })

    test('can toggle routes layer', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const routesLabel = page.locator('label:has-text("Routes")').first()
      const routesToggle = routesLabel.locator('input.toggle')

      const initialState = await routesToggle.isChecked()

      await routesLabel.click()
      await page.waitForTimeout(500)

      const newState = await routesToggle.isChecked()
      expect(newState).toBe(!initialState)
    })

    test('multiple layers can be toggled simultaneously', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const pointsToggle = page.locator('label:has-text("Points")').first().locator('input.toggle')
      const routesToggle = page.locator('label:has-text("Routes")').first().locator('input.toggle')

      if (!(await pointsToggle.isChecked())) {
        await pointsToggle.check()
        await page.waitForTimeout(500)
      }
      if (!(await routesToggle.isChecked())) {
        await routesToggle.check()
        await page.waitForTimeout(500)
      }

      const pointsVisible = await getLayerVisibility(page, 'points')
      const routesVisible = await getLayerVisibility(page, 'routes')

      expect(pointsVisible).toBe(true)
      expect(routesVisible).toBe(true)
    })
  })

  test.describe('Settings Persistence', () => {
    test('layer toggle state persists in localStorage', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const pointsToggle = page.locator('label:has-text("Points")').first().locator('input.toggle')
      const initialState = await pointsToggle.isChecked()

      const settings = await page.evaluate(() => {
        return localStorage.getItem('dawarich-maps--maplibre-settings')
      })

      expect(settings).toBeTruthy()

      const parsed = JSON.parse(settings)
      expect(parsed).toHaveProperty('pointsVisible')
      expect(parsed.pointsVisible).toBe(initialState)
    })
  })

  test.describe('Advanced Settings', () => {
    test('displays advanced settings options', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      const panel = page.locator('[data-tab-content="settings"]')
      await expect(panel).toBeVisible()
    })
  })
})
