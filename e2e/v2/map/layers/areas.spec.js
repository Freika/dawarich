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
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)

      // Click Layers tab
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await expect(areasToggle).toBeVisible()
    })

    test('can toggle areas layer', async ({ page }) => {
      // Open settings panel
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const map = controller?.map
        return map && map.getSource('draw-source') !== undefined
      })
      expect(hasDrawLayers).toBe(true)
    })

    test('should open modal when area is drawn', async ({ page }) => {
      // Enable creation mode
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
    })

    test('should display radius and location in modal', async ({ page }) => {
      // Enable creation mode and draw area
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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

      // Wait for radius to have a non-empty text content (it's a span, not an input)
      await page.waitForFunction(() => {
        const elem = document.querySelector('[data-area-creation-v2-target="radiusDisplay"]')
        return elem && elem.textContent && elem.textContent !== '0'
      }, { timeout: 3000 })

      // Verify radius has a value
      const radiusValue = await radiusDisplay.textContent()
      expect(parseInt(radiusValue)).toBeGreaterThan(0)

      // Verify hidden latitude/longitude inputs are populated
      const latInput = page.locator('[data-area-creation-v2-target="latitudeInput"]')
      const lngInput = page.locator('[data-area-creation-v2-target="longitudeInput"]')

      const latValue = await latInput.inputValue()
      const lngValue = await lngInput.inputValue()

      expect(parseFloat(latValue)).not.toBeNaN()
      expect(parseFloat(lngValue)).not.toBeNaN()
    })

    test('should create area and enable layer when submitted', async ({ page }) => {
      // Draw area
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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
      // Wait for radius to have a non-empty text content (it's a span, not an input)
      await page.waitForFunction(() => {
        const elem = document.querySelector('[data-area-creation-v2-target="radiusDisplay"]')
        return elem && elem.textContent && elem.textContent !== '0'
      }, { timeout: 3000 })

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
        await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
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

  test.describe('Area Deletion', () => {
    test('should show Delete button when clicking on an area', async ({ page }) => {
      // Enable areas layer first
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="layers"]').click()
      await page.waitForTimeout(200)

      const areasToggle = page.locator('label:has-text("Areas")').first().locator('input.toggle')
      await areasToggle.check()
      await page.waitForTimeout(1000)

      // Close settings
      await page.click('button[title="Close panel"]')
      await page.waitForTimeout(500)

      // Check if there are any areas
      const hasAreas = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const areasLayer = controller?.layerManager?.getLayer('areas')
        return areasLayer?.data?.features?.length > 0
      })

      if (!hasAreas) {
        console.log('No areas found, skipping test')
        test.skip()
        return
      }

      // Get an area ID
      const areaId = await page.evaluate(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const areasLayer = controller?.layerManager?.getLayer('areas')
        return areasLayer?.data?.features[0]?.properties?.id
      })

      if (!areaId) {
        console.log('No area ID found, skipping test')
        test.skip()
        return
      }

      // Simulate clicking on an area
      await page.evaluate((id) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')

        const mockEvent = {
          features: [{
            properties: {
              id: id,
              name: 'Test Area',
              radius: 500,
              latitude: 40.7128,
              longitude: -74.0060
            }
          }]
        }
        controller.eventHandlers.handleAreaClick(mockEvent)
      }, areaId)

      await page.waitForTimeout(1000)

      // Verify info display is shown
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      await expect(infoDisplay).toBeVisible({ timeout: 5000 })

      // Verify Delete button exists and has error styling (red)
      const deleteButton = infoDisplay.locator('button:has-text("Delete")')
      await expect(deleteButton).toBeVisible()
      await expect(deleteButton).toHaveClass(/btn-error/)
    })

    test('should delete area with confirmation and update map', async ({ page }) => {
      // First create an area to delete
      await page.locator('[data-action="click->maps--maplibre#toggleSettings"]').first().click()
      await page.waitForTimeout(200)
      await page.locator('button[data-tab="tools"]').click()
      await page.waitForTimeout(200)
      await page.locator('button:has-text("Create an Area")').click()
      await page.waitForTimeout(500)

      const mapCanvas = page.locator('.maplibregl-canvas')
      await mapCanvas.click({ position: { x: 400, y: 300 } })
      await page.waitForTimeout(300)
      await mapCanvas.click({ position: { x: 450, y: 350 } })

      const areaModal = page.locator('[data-area-creation-v2-target="modal"]')
      await expect(areaModal).toHaveClass(/modal-open/, { timeout: 5000 })

      const radiusDisplay = page.locator('[data-area-creation-v2-target="radiusDisplay"]')
      // Wait for radius to have a non-empty text content (it's a span, not an input)
      await page.waitForFunction(() => {
        const elem = document.querySelector('[data-area-creation-v2-target="radiusDisplay"]')
        return elem && elem.textContent && elem.textContent !== '0'
      }, { timeout: 3000 })

      const areaName = `Delete Test Area ${Date.now()}`
      await page.locator('[data-area-creation-v2-target="nameInput"]').fill(areaName)

      // Click the submit button specifically in the area creation modal
      await page.locator('[data-area-creation-v2-target="submitButton"]').click()

      // Wait for creation success
      await expect(page.locator('.toast:has-text("successfully")')).toBeVisible({ timeout: 10000 })
      await page.waitForTimeout(2000)

      // Get the created area ID
      const areaId = await page.evaluate((name) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const areasLayer = controller?.layerManager?.getLayer('areas')
        const area = areasLayer?.data?.features?.find(f => f.properties.name === name)
        return area?.properties?.id
      }, areaName)

      if (!areaId) {
        console.log('Created area not found in layer, skipping delete test')
        test.skip()
        return
      }

      // Simulate clicking on the area
      await page.evaluate((id) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')

        const mockEvent = {
          features: [{
            properties: {
              id: id,
              name: 'Test Area',
              radius: 500,
              latitude: 40.7128,
              longitude: -74.0060
            }
          }]
        }
        controller.eventHandlers.handleAreaClick(mockEvent)
      }, areaId)

      await page.waitForTimeout(1000)

      // Setup confirmation dialog handler before clicking delete
      const dialogPromise = page.waitForEvent('dialog')

      // Click Delete button
      const infoDisplay = page.locator('[data-maps--maplibre-target="infoDisplay"]')
      const deleteButton = infoDisplay.locator('button:has-text("Delete")')
      await expect(deleteButton).toBeVisible({ timeout: 5000 })
      await deleteButton.click()

      // Handle the confirmation dialog
      const dialog = await dialogPromise
      expect(dialog.message()).toContain('Delete area')
      await dialog.accept()

      // Wait for deletion toast
      await expect(page.locator('.toast:has-text("deleted successfully")')).toBeVisible({ timeout: 10000 })

      // Verify the area was removed from the layer
      await page.waitForTimeout(1500)
      const areaStillExists = await page.evaluate((name) => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        const areasLayer = controller?.layerManager?.getLayer('areas')
        return areasLayer?.data?.features?.some(f => f.properties.name === name)
      }, areaName)

      expect(areaStillExists).toBe(false)

      // Verify info display is closed
      await expect(infoDisplay).not.toBeVisible()
    })
  })
})
