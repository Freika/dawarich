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
      // Open settings panel
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await expect(areasToggle).toBeVisible()
    })

    test('can toggle areas layer', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await areasToggle.check()
      await page.waitForTimeout(500)

      const isChecked = await areasToggle.isChecked()
      expect(isChecked).toBe(true)
    })
  })

  test.describe('Area Creation', () => {
    test('should have Create an Area button in Tools tab', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Tools tab
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)

      // Verify Create an Area button exists
      const createAreaButton = page.locator('button:has-text("Create an Area")')
      await expect(createAreaButton).toBeVisible()
    })

    test('should change cursor to crosshair when Create an Area is clicked', async ({ page }) => {
      // Open settings
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)

      // Click Create an Area
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      // Verify cursor changed to crosshair
      const cursorStyle = await page.evaluate(() => {
        const canvas = document.querySelector('.maplibregl-canvas')
        return canvas ? window.getComputedStyle(canvas).cursor : null
      })
      expect(cursorStyle).toBe('crosshair')
    })

    test('should show area preview while drawing', async ({ page }) => {
      // Enable creation mode
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      // First click to set center
      const mapCanvas = page.locator('.maplibregl-canvas')
      await mapCanvas.click({ position: { x: 400, y: 300 } })
      await page.waitForTimeout(300)

      // Move mouse to create radius preview
      await mapCanvas.hover({ position: { x: 450, y: 350 } })
      await page.waitForTimeout(300)

      // Verify draw layers exist
      const hasDrawLayers = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps-v2')
        const map = controller?.map
        return map && map.getSource('draw-source') !== undefined
      })
      expect(hasDrawLayers).toBe(true)
    })

    test('should open modal when area is drawn', async ({ page }) => {
      // Enable creation mode
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      // Draw area: first click for center, second click to finish
      const mapCanvas = page.locator('.maplibregl-canvas')
      await mapCanvas.click({ position: { x: 400, y: 300 } })
      await page.waitForTimeout(300)
      await mapCanvas.click({ position: { x: 450, y: 350 } })

      // Wait for area creation modal to open
      const areaModal = page.locator('[data-area-creation-v2-target="modal"]')
      await expect(areaModal).toHaveClass(/modal-open/, { timeout: 5000 })

      // Verify form fields exist
      await expect(page.locator('[data-area-creation-v2-target="nameInput"]')).toBeVisible()
      await expect(page.locator('[data-area-creation-v2-target="radiusDisplay"]')).toBeVisible()
      await expect(page.locator('[data-area-creation-v2-target="locationDisplay"]')).toBeVisible()
    })

    test('should display radius and location in modal', async ({ page }) => {
      // Enable creation mode and draw area
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      const mapCanvas = page.locator('.maplibregl-canvas')
      await mapCanvas.click({ position: { x: 400, y: 300 } })
      await page.waitForTimeout(300)
      await mapCanvas.click({ position: { x: 450, y: 350 } })

      // Wait for modal to open
      const areaModal = page.locator('[data-area-creation-v2-target="modal"]')
      await expect(areaModal).toHaveClass(/modal-open/, { timeout: 5000 })

      // Wait for fields to be populated
      const radiusDisplay = page.locator('[data-area-creation-v2-target="radiusDisplay"]')
      const locationDisplay = page.locator('[data-area-creation-v2-target="locationDisplay"]')

      // Wait for radius to have a non-empty value
      await expect(radiusDisplay).not.toHaveValue('', { timeout: 3000 })

      // Verify radius has a value
      const radiusValue = await radiusDisplay.inputValue()
      expect(parseInt(radiusValue)).toBeGreaterThan(0)

      // Verify location has a value (should be coordinates)
      const locationValue = await locationDisplay.inputValue()
      expect(locationValue).toMatch(/-?\d+\.\d+,\s*-?\d+\.\d+/)
    })

    test('should create area and enable layer when submitted', async ({ page }) => {
      // Draw area
      await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      const mapCanvas = page.locator('.maplibregl-canvas')
      await mapCanvas.click({ position: { x: 400, y: 300 } })
      await page.waitForTimeout(300)
      await mapCanvas.click({ position: { x: 450, y: 350 } })

      // Wait for modal to be open
      const areaModal = page.locator('[data-area-creation-v2-target="modal"]')
      await expect(areaModal).toHaveClass(/modal-open/, { timeout: 5000 })

      // Wait for fields to be populated before filling the form
      const radiusDisplay = page.locator('[data-area-creation-v2-target="radiusDisplay"]')
      await expect(radiusDisplay).not.toHaveValue('', { timeout: 3000 })

      await page.locator('[data-area-creation-v2-target="nameInput"]').fill('Test Area E2E')

      // Listen for console errors
      page.on('console', msg => {
        if (msg.type() === 'error') {
          console.log('Browser console error:', msg.text())
        }
      })

      // Handle potential alert dialog
      let dialogMessage = null
      page.once('dialog', async dialog => {
        dialogMessage = dialog.message()
        console.log('Dialog appeared:', dialogMessage)
        await dialog.accept()
      })

      // Wait for API response
      const [response] = await Promise.all([
        page.waitForResponse(
          response => response.url().includes('/api/v1/areas') && response.request().method() === 'POST',
          { timeout: 10000 }
        ),
        page.locator('button[type="submit"]:has-text("Create Area")').click()
      ])

      const status = response.status()
      console.log('API response status:', status)

      if (status >= 200 && status < 300) {
        // Success - verify modal closes (modal-open class is removed)
        await expect(areaModal).not.toHaveClass(/modal-open/, { timeout: 5000 })

        // Wait for area:created event to be processed
        await page.waitForTimeout(1000)

        // Verify areas layer is now enabled
        await page.locator('[data-action="click->maps-v2#toggleSettings"]').first().click()
        await page.waitForTimeout(200)
        await page.locator('button[data-tab="layers"]').click()
        await page.waitForTimeout(200)

        const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
        await expect(areasToggle).toBeChecked({ timeout: 3000 })
      } else {
        // API failed - log the error and fail the test with helpful info
        const responseBody = await response.text()
        throw new Error(`API call failed with status ${status}: ${responseBody}`)
      }
    })
  })
})
