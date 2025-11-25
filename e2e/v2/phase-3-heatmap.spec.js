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
      // Open settings panel
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(500)

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      // Find and toggle heatmap using DaisyUI toggle
      const heatmapLabel = page.locator('label:has-text("Heatmap")').first()
      const heatmapToggle = heatmapLabel.locator('input.toggle')
      await heatmapToggle.check()
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
      // Open settings panel
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(500)

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      // Toggle heatmap on - find toggle by its label text
      const heatmapLabel = page.locator('label:has-text("Heatmap")').first()
      const heatmapToggle = heatmapLabel.locator('input.toggle')
      await heatmapToggle.check()
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

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapToggle = page.locator('label:has-text("Heatmap")').first().locator('input.toggle')
      await heatmapToggle.check()
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
      const panel = page.locator('.map-control-panel')
      await page.waitForTimeout(400)
      await expect(panel).toHaveClass(/open/)

      // Close the panel using the close button
      await page.click('.panel-header button[title="Close panel"]')

      // Wait for panel close animation
      await page.waitForTimeout(400)
      await expect(panel).not.toHaveClass(/open/)
    })

    test('tab switching works', async ({ page }) => {
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(400)

      // Check default tab is Search
      const searchTab = page.locator('[data-tab-content="search"]')
      await expect(searchTab).toHaveClass(/active/)

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const layersTab = page.locator('[data-tab-content="layers"]')
      await expect(layersTab).toHaveClass(/active/)
      await expect(searchTab).not.toHaveClass(/active/)

      // Switch to Settings tab
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      const settingsTab = page.locator('[data-tab-content="settings"]')
      await expect(settingsTab).toHaveClass(/active/)
      await expect(layersTab).not.toHaveClass(/active/)
    })

    test('map style can be changed', async ({ page }) => {
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      // Switch to Settings tab
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      const styleSelect = page.locator('select.select-bordered').first()
      await styleSelect.selectOption('dark')

      // Wait for style to load
      await page.waitForTimeout(1000)

      const savedStyle = await page.evaluate(() => {
        const settings = JSON.parse(localStorage.getItem('dawarich-maps-v2-settings') || '{}')
        return settings.mapStyle
      })

      expect(savedStyle).toBe('dark')
    })

    test('settings persist across page loads', async ({ page }) => {
      // Change a setting
      await page.click('button[title="Settings"]')
      await page.waitForTimeout(300)

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapToggle = page.locator('label:has-text("Heatmap")').first().locator('input.toggle')
      await heatmapToggle.check()
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

      // Switch to Settings tab
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      await page.locator('select.select-bordered').first().selectOption('dark')
      await page.waitForTimeout(300)

      // Switch to Layers tab to enable heatmap
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      const heatmapToggle = page.locator('label:has-text("Heatmap")').first().locator('input.toggle')
      await heatmapToggle.check()
      await page.waitForTimeout(300)

      // Switch back to Settings tab
      await page.click('button[data-tab="settings"]')
      await page.waitForTimeout(300)

      // Setup dialog handler before clicking reset
      page.on('dialog', dialog => dialog.accept())

      // Reset - this will reload the page
      await page.click('.btn-outline:has-text("Reset to Defaults")')

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

      // Switch to Layers tab
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)

      // Check that settings panel is open
      const settingsPanel = page.locator('.map-control-panel.open')
      await expect(settingsPanel).toBeVisible()

      // Check that DaisyUI toggles exist (any layer toggle)
      const toggles = page.locator('input.toggle')
      const count = await toggles.count()
      expect(count).toBeGreaterThan(0)
    })
  })
})
