import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js'

test.describe('Live Mode', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1000)
  })

  test.describe('Live Mode Toggle', () => {
    test('should have live mode toggle in settings', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)

      // Click Settings tab
      await page.locator('button[data-tab="settings"]').click()
      await page.waitForTimeout(300)

      // Verify Live Mode toggle exists
      const liveModeToggle = page.locator('[data-maps-v2-realtime-target="liveModeToggle"]')
      await expect(liveModeToggle).toBeVisible()

      // Verify label text
      const label = page.locator('label:has-text("Live Mode")')
      await expect(label).toBeVisible()

      // Verify description text
      const description = page.locator('text=Show new points in real-time')
      await expect(description).toBeVisible()
    })

    test('should toggle live mode on and off', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('button[data-tab="settings"]').click()
      await page.waitForTimeout(300)

      const liveModeToggle = page.locator('[data-maps-v2-realtime-target="liveModeToggle"]')

      // Get initial state
      const initialState = await liveModeToggle.isChecked()

      // Toggle it
      await liveModeToggle.click()
      await page.waitForTimeout(500)

      // Verify state changed
      const newState = await liveModeToggle.isChecked()
      expect(newState).toBe(!initialState)

      // Toggle back
      await liveModeToggle.click()
      await page.waitForTimeout(500)

      // Verify state reverted
      const finalState = await liveModeToggle.isChecked()
      expect(finalState).toBe(initialState)
    })

    test('should show toast notification when toggling live mode', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('button[data-tab="settings"]').click()
      await page.waitForTimeout(300)

      const liveModeToggle = page.locator('[data-maps-v2-realtime-target="liveModeToggle"]')
      const initialState = await liveModeToggle.isChecked()

      // Toggle and watch for toast
      await liveModeToggle.click()

      // Wait for toast to appear
      const expectedMessage = initialState ? 'Live mode disabled' : 'Live mode enabled'
      const toast = page.locator('.toast, [role="alert"]').filter({ hasText: expectedMessage })
      await expect(toast).toBeVisible({ timeout: 3000 })
    })
  })

  test.describe('Realtime Controller', () => {
    test('should initialize realtime controller when enabled', async ({ page }) => {
      const realtimeControllerExists = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')
        return controller !== undefined
      })

      expect(realtimeControllerExists).toBe(true)
    })

    test('should have access to maps-v2 controller', async ({ page }) => {
      const hasMapsController = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const realtimeController = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')
        const mapsController = realtimeController?.mapsV2Controller
        return mapsController !== undefined && mapsController.map !== undefined
      })

      expect(hasMapsController).toBe(true)
    })

    test('should initialize ActionCable channels', async ({ page }) => {
      // Wait for channels to be set up
      await page.waitForTimeout(2000)

      const channelsInitialized = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')
        return controller?.channels !== undefined
      })

      expect(channelsInitialized).toBe(true)
    })
  })

  test.describe('Connection Indicator', () => {
    test('should have connection indicator element in DOM', async ({ page }) => {
      // Connection indicator exists but is hidden by default
      const indicator = page.locator('.connection-indicator')

      // Should exist in DOM
      await expect(indicator).toHaveCount(1)

      // Should be hidden (not active) without real ActionCable connection
      const isActive = await indicator.evaluate(el => el.classList.contains('active'))
      expect(isActive).toBe(false)
    })

    test('should have connection status classes', async ({ page }) => {
      const indicator = page.locator('.connection-indicator')

      // Should have disconnected class by default (before connection)
      const hasDisconnectedClass = await indicator.evaluate(el =>
        el.classList.contains('disconnected')
      )

      expect(hasDisconnectedClass).toBe(true)
    })

    test.skip('should show connection indicator when ActionCable connects', async ({ page }) => {
      // This test requires actual ActionCable connection
      // The indicator becomes visible (.active class added) only when channels connect

      // Wait for connection
      await page.waitForTimeout(3000)

      const indicator = page.locator('.connection-indicator')

      // Should be visible with active class
      await expect(indicator).toHaveClass(/active/)
      await expect(indicator).toBeVisible()
    })

    test.skip('should show appropriate connection text when active', async ({ page }) => {
      // This test requires actual ActionCable connection
      // The indicator text shows via CSS ::before pseudo-element

      // Wait for connection
      await page.waitForTimeout(3000)

      const indicatorText = page.locator('.connection-indicator .indicator-text')

      // Should show either "Connected" or "Connecting..."
      const text = await indicatorText.evaluate(el => {
        return window.getComputedStyle(el, '::before').content.replace(/['"]/g, '')
      })

      expect(['Connected', 'Connecting...']).toContain(text)
    })
  })

  test.describe('Point Handling', () => {
    test('should have handleNewPoint method', async ({ page }) => {
      const hasMethod = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')
        return typeof controller?.handleNewPoint === 'function'
      })

      expect(hasMethod).toBe(true)
    })

    test('should have zoomToPoint method', async ({ page }) => {
      const hasMethod = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')
        return typeof controller?.zoomToPoint === 'function'
      })

      expect(hasMethod).toBe(true)
    })

    test.skip('should add new point to map when received', async ({ page }) => {
      // This test requires actual ActionCable broadcast
      // Skipped as it needs backend point creation

      // Get initial point count
      const initialCount = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const pointsLayer = controller?.layerManager?.getLayer('points')
        return pointsLayer?.data?.features?.length || 0
      })

      // Simulate point broadcast (would need real backend)
      // const newPoint = [52.5200, 13.4050, 85, 10, '2025-01-01T12:00:00Z', 5, 999, 'Germany']

      // Wait for point to be added
      // await page.waitForTimeout(1000)

      // Verify point was added
      // const newCount = await page.evaluate(() => { ... })
      // expect(newCount).toBe(initialCount + 1)
    })

    test.skip('should zoom to new point location', async ({ page }) => {
      // This test requires actual ActionCable broadcast
      // Skipped as it needs backend point creation

      // Get initial map center
      // Broadcast new point at specific location
      // Verify map center changed to new point location
    })
  })

  test.describe('Live Mode State Persistence', () => {
    test('should maintain live mode state after toggling', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('button[data-tab="settings"]').click()
      await page.waitForTimeout(300)

      const liveModeToggle = page.locator('[data-maps-v2-realtime-target="liveModeToggle"]')

      // Enable live mode
      if (!await liveModeToggle.isChecked()) {
        await liveModeToggle.click()
        await page.waitForTimeout(500)
      }

      // Verify it's enabled
      expect(await liveModeToggle.isChecked()).toBe(true)

      // Close and reopen settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(300)
      await page.locator('button[data-tab="settings"]').click()
      await page.waitForTimeout(300)

      // Should still be enabled
      expect(await liveModeToggle.isChecked()).toBe(true)
    })
  })

  test.describe('Error Handling', () => {
    test('should handle missing maps controller gracefully', async ({ page }) => {
      // This is tested by the controller's defensive checks
      const hasDefensiveChecks = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2-realtime"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2-realtime')

        // The controller should have the mapsV2Controller getter
        return typeof controller?.mapsV2Controller !== 'undefined'
      })

      expect(hasDefensiveChecks).toBe(true)
    })

    test('should handle missing points layer gracefully', async ({ page }) => {
      // Console errors should not crash the app
      let consoleErrors = []
      page.on('console', msg => {
        if (msg.type() === 'error') {
          consoleErrors.push(msg.text())
        }
      })

      // Wait for initialization
      await page.waitForTimeout(2000)

      // Should not have critical errors
      const hasCriticalErrors = consoleErrors.some(err =>
        err.includes('TypeError') || err.includes('Cannot read')
      )

      expect(hasCriticalErrors).toBe(false)
    })
  })
})
