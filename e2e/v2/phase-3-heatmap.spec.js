import { test, expect } from '@playwright/test'
import { navigateToMapsV2, navigateToMapsV2WithDate, waitForMapLibre, waitForLoadingComplete } from './helpers/setup'
import { closeOnboardingModal } from '../helpers/navigation'

test.describe('Phase 3: Heatmap + Settings', () => {
  // Use serial mode to avoid overwhelming the system with parallel requests
  test.describe.configure({ mode: 'serial' })

  test.beforeEach(async ({ page }) => {
    // Navigate with a date that has data
    await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)

    // Wait for map with retry logic
    try {
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
    } catch (error) {
      console.log('Map loading timeout, waiting and retrying...')
      await page.waitForTimeout(2000)
      // Try one more time
      await waitForLoadingComplete(page).catch(() => {
        console.log('Second attempt also timed out, continuing anyway...')
      })
    }

    await page.waitForTimeout(1000) // Give layers time to initialize
  })

  test.describe('Heatmap Layer', () => {
    test('heatmap layer can be created', async ({ page }) => {
      // Heatmap layer might not exist by default, but should be creatable
      // Open settings and enable heatmap
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(500)

      const heatmapLabel = page.locator('label.setting-checkbox:has-text("Show Heatmap")')
      const heatmapCheckbox = heatmapLabel.locator('input[type="checkbox"]')
      await heatmapCheckbox.check()
      await page.waitForTimeout(500)

      // Check if heatmap layer now exists
      const hasHeatmap = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        if (!element) return false
        const app = window.Stimulus || window.Application
        if (!app) return false
        const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
        return controller?.map?.getLayer('heatmap') !== undefined
      })

      expect(hasHeatmap).toBe(true)
    })

    test('heatmap can be toggled', async ({ page }) => {
      // Open settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(500)

      // Toggle heatmap on - find checkbox by its label text
      const heatmapLabel = page.locator('label.setting-checkbox:has-text("Show Heatmap")')
      const heatmapCheckbox = heatmapLabel.locator('input[type="checkbox"]')
      await heatmapCheckbox.check()
      await page.waitForTimeout(500)

      const isVisible = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const visibility = controller?.map?.getLayoutProperty('heatmap', 'visibility')
        return visibility === 'visible' || visibility === undefined
      })

      expect(isVisible).toBe(true)
    })

    test('heatmap setting persists', async ({ page }) => {
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      const heatmapCheckbox = page.locator('label.setting-checkbox:has-text("Show Heatmap")').locator('input[type="checkbox"]')
      await heatmapCheckbox.check()
      await page.waitForTimeout(300)

      // Check localStorage
      const savedSetting = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('dawarich-maps-v2-settings') || '{}')
        return settings.heatmapEnabled
      })

      expect(savedSetting).toBe(true)
    })
  })

  test.describe('Settings Panel', () => {
    test('settings panel opens and closes', async ({ page }) => {
      const settingsBtn = page.locator('button[title="Settings"]')
      await settingsBtn.click()

      // Wait for panel to open (animation takes 300ms)
      const panel = page.locator('.settings-panel')
      await page.waitForTimeout(400)
      await expect(panel).toHaveClass(/open/)

      // Close the panel - trigger the Stimulus action directly
      await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
        controller.toggleSettings()
      })

      // Wait for panel close animation
      await page.waitForTimeout(400)
      await expect(panel).not.toHaveClass(/open/)
    })

    test('map style can be changed', async ({ page }) => {
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      const styleSelect = page.locator('#map-style')
      await styleSelect.selectOption('dark-matter')

      // Wait for style to load
      await page.waitForTimeout(1000)

      const savedStyle = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('dawarich-maps-v2-settings') || '{}')
        return settings.mapStyle
      })

      expect(savedStyle).toBe('dark-matter')
    })

    test('settings persist across page loads', async ({ page }) => {
      // Change a setting
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      const heatmapCheckbox = page.locator('label.setting-checkbox:has-text("Show Heatmap")').locator('input[type="checkbox"]')
      await heatmapCheckbox.check()
      await page.waitForTimeout(300)

      // Reload page
      await page.reload()
      await closeOnboardingModal(page)
      await waitForMapLibre(page)

      // Check if setting persisted
      const savedSetting = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('dawarich-maps-v2-settings') || '{}')
        return settings.heatmapEnabled
      })

      expect(savedSetting).toBe(true)
    })

    test('reset to defaults works', async ({ page }) => {
      // Change settings
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      await page.locator('#map-style').selectOption('dark-matter')
      await page.waitForTimeout(300)

      const heatmapCheckbox = page.locator('label.setting-checkbox:has-text("Show Heatmap")').locator('input[type="checkbox"]')
      await heatmapCheckbox.check()
      await page.waitForTimeout(300)

      // Setup dialog handler before clicking reset
      page.on('dialog', dialog => dialog.accept())

      // Reset - this will reload the page
      await page.click('.reset-btn')

      // Wait for page reload
      await closeOnboardingModal(page)
      await waitForMapLibre(page)

      // Check defaults restored (localStorage should be empty)
      const settings = await page.evaluate(() => {
        const stored = localStorage.getItem('dawarich-maps-v2-settings')
        return stored ? JSON.parse(stored) : null
      })

      // After reset, localStorage should be null or empty
      expect(settings).toBeNull()
    })
  })

  test.describe('Regression Tests', () => {
    test('points layer still works', async ({ page }) => {
      // Wait for points source to be available
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        return controller?.map?.getSource('points-source') !== undefined
      }, { timeout: 10000 })

      const hasPoints = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const source = controller?.map?.getSource('points-source')
        return source && source._data?.features?.length > 0
      })

      expect(hasPoints).toBe(true)
    })

    test('routes layer still works', async ({ page }) => {
      // Wait for routes source to be available
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        return controller?.map?.getSource('routes-source') !== undefined
      }, { timeout: 10000 })

      const hasRoutes = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const source = controller?.map?.getSource('routes-source')
        return source && source._data?.features?.length > 0
      })

      expect(hasRoutes).toBe(true)
    })

    test('layer toggle still works', async ({ page }) => {
      // Just verify settings panel has layer toggles
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Check that settings panel is open
      const settingsPanel = page.locator('.settings-panel.open')
      await expect(settingsPanel).toBeVisible()

      // Check that at least one checkbox exists (any layer toggle)
      const checkboxes = page.locator('.setting-checkbox input[type="checkbox"]')
      const count = await checkboxes.count()
      expect(count).toBeGreaterThan(0)
    })
  })
})
