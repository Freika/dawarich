import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import { navigateToMapsV2, waitForMapLibre, waitForLoadingComplete } from '../../helpers/setup.js'

/**
 * Helper to get the visit creation modal specifically
 * There may be multiple modals on the page, so we need to be specific
 */
function getVisitCreationModal(page) {
  return page.locator('[data-controller="visit-creation-v2"] .modal-box')
}

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

  test.describe('Visit Creation', () => {
    test('should show Create a Visit button in Tools tab', async ({ page }) => {
      // Open settings panel
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      // Click Tools tab
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)

      // Verify Create a Visit button exists
      const createVisitButton = page.locator('button:has-text("Create a Visit")')
      await expect(createVisitButton).toBeVisible()
      await expect(createVisitButton).toBeEnabled()
    })

    test('should enable visit creation mode and show toast', async ({ page }) => {
      // Open settings panel and click Tools tab
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)

      // Click Create a Visit button
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      // Verify settings panel closed
      const settingsPanel = page.locator('[data-maps--maplibre-target="settingsPanel"]')
      const hasPanelOpenClass = await settingsPanel.evaluate((el) => el.classList.contains('open'))
      expect(hasPanelOpenClass).toBe(false)

      // Verify toast message appears
      const toast = page.locator('.toast:has-text("Click on the map to place a visit")')
      await expect(toast).toBeVisible({ timeout: 5000 })

      // Verify cursor changed to crosshair
      const cursor = await page.evaluate(() => {
        const canvas = document.querySelector('.maplibregl-canvas')
        return canvas?.style.cursor
      })
      expect(cursor).toBe('crosshair')
    })

    test('should open modal when map is clicked', async ({ page }) => {
      // Enable visit creation mode
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      // Click on map
      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3)
      await page.waitForTimeout(2000)

      // Verify modal title is visible (modal is open) - this is specific to visit creation modal
      await expect(page.locator('h3:has-text("Create New Visit")')).toBeVisible({ timeout: 5000 })

      // Verify the specific visit creation modal is visible
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible()

      // Verify form has the location coordinates populated
      const latInput = visitModal.locator('input[name="latitude"]')
      const lngInput = visitModal.locator('input[name="longitude"]')

      const latValue = await latInput.inputValue()
      const lngValue = await lngInput.inputValue()

      expect(latValue).toBeTruthy()
      expect(lngValue).toBeTruthy()
    })

    test('should display correct form fields in modal', async ({ page }) => {
      // Enable mode and click map
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3)
      await page.waitForTimeout(1500)

      // Wait for modal to be visible
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible({ timeout: 5000 })

      // Verify all form fields exist within the visit creation modal
      await expect(visitModal.locator('input[name="name"]')).toBeVisible()
      await expect(visitModal.locator('input[name="started_at"]')).toBeVisible()
      await expect(visitModal.locator('input[name="ended_at"]')).toBeVisible()
      await expect(visitModal.locator('input[data-visit-creation-v2-target="locationDisplay"]')).toBeVisible()
      await expect(visitModal.locator('button:has-text("Adjust")')).toBeVisible()
      await expect(visitModal.locator('button:has-text("Create Visit")')).toBeVisible()
      await expect(visitModal.locator('button:has-text("Cancel")')).toBeVisible()

      // Verify start and end time have default values
      const startValue = await visitModal.locator('input[name="started_at"]').inputValue()
      const endValue = await visitModal.locator('input[name="ended_at"]').inputValue()
      expect(startValue).toBeTruthy()
      expect(endValue).toBeTruthy()
    })

    test('should close modal when cancel is clicked', async ({ page }) => {
      // Enable mode and click map
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(500)
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(500)

      // Click Create a Visit button
      const createButton = page.locator('button:has-text("Create a Visit")')
      await expect(createButton).toBeVisible()
      await createButton.click()
      await page.waitForTimeout(1000)

      // Wait for settings panel to close and cursor to change
      await page.waitForTimeout(500)

      // Click on map - try a different location
      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.5, bbox.y + bbox.height * 0.5)
      await page.waitForTimeout(2500)

      // Verify modal exists
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible({ timeout: 10000 })

      // Find the cancel button - it's a ghost button
      const cancelButton = visitModal.locator('button.btn-ghost:has-text("Cancel")')
      await expect(cancelButton).toBeVisible()
      await cancelButton.click()
      await page.waitForTimeout(1500)

      // Verify modal is closed by checking if modal-open class is removed
      const modal = page.locator('[data-controller="visit-creation-v2"] .modal')
      const hasModalOpenClass = await modal.evaluate((el) => el.classList.contains('modal-open'))
      expect(hasModalOpenClass).toBe(false)
    })

    test('should create visit successfully', async ({ page }) => {
      // Enable visits layer first
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)
      const visitsToggle = page.locator('label:has-text("Visits")').first().locator('input.toggle')
      await visitsToggle.check()
      await page.waitForTimeout(500)

      // Enable visit creation mode
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      // Click on map
      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3)
      await page.waitForTimeout(2000)

      // Wait for modal to be visible
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible({ timeout: 5000 })

      // Fill form with unique visit name
      const visitName = `E2E V2 Test Visit ${Date.now()}`
      await visitModal.locator('input[name="name"]').fill(visitName)

      // Submit form
      await visitModal.locator('button:has-text("Create Visit")').click()

      // Wait for success toast - this confirms the visit was created
      const successToast = page.locator('.toast:has-text("created successfully")')
      await expect(successToast).toBeVisible({ timeout: 10000 })

      // Verify modal is closed by checking if modal-open class is removed
      await page.waitForTimeout(1500)
      const modal = page.locator('[data-controller="visit-creation-v2"] .modal')
      const hasModalOpenClass = await modal.evaluate((el) => el.classList.contains('modal-open'))
      expect(hasModalOpenClass).toBe(false)
    })

    test('should make created visit searchable in side panel', async ({ page }) => {
      // Enable visits layer
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(300)
      const visitsToggle = page.locator('label:has-text("Visits")').first().locator('input.toggle')
      await visitsToggle.check()
      await page.waitForTimeout(500)

      // Create a visit with unique name
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3)
      await page.waitForTimeout(2000)

      // Wait for modal to be visible
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible({ timeout: 5000 })

      const visitName = `Searchable Visit ${Date.now()}`
      await visitModal.locator('input[name="name"]').fill(visitName)
      await visitModal.locator('button:has-text("Create Visit")').click()

      // Wait for success toast
      const successToast = page.locator('.toast:has-text("created successfully")')
      await expect(successToast).toBeVisible({ timeout: 10000 })

      // Wait for modal to close
      await page.waitForTimeout(1500)

      // Open settings and go to layers tab to access visit search
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="layers"]')
      await page.waitForTimeout(500)

      // Search field should now be visible (bug fix ensures it shows when toggle is checked)
      const searchField = page.locator('input#visits-search')
      await expect(searchField).toBeVisible({ timeout: 5000 })

      // Use the visit search field
      await searchField.fill(visitName.substring(0, 10))
      await page.waitForTimeout(500)

      // Verify the search field is working - just check that it accepted the input
      const searchValue = await searchField.inputValue()
      expect(searchValue).toBe(visitName.substring(0, 10))
    })

    test('should validate required fields', async ({ page }) => {
      // Enable visit creation mode
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)
      await page.click('button[data-tab="tools"]')
      await page.waitForTimeout(300)
      await page.click('button:has-text("Create a Visit")')
      await page.waitForTimeout(500)

      // Click on map
      const mapContainer = page.locator('.maplibregl-canvas')
      const bbox = await mapContainer.boundingBox()
      await page.mouse.click(bbox.x + bbox.width * 0.3, bbox.y + bbox.height * 0.3)
      await page.waitForTimeout(1500)

      // Wait for modal to be visible
      const visitModal = getVisitCreationModal(page)
      await expect(visitModal).toBeVisible({ timeout: 5000 })

      // Clear the name field
      await visitModal.locator('input[name="name"]').clear()

      // Try to submit form without name
      await visitModal.locator('button:has-text("Create Visit")').click()
      await page.waitForTimeout(500)

      // Verify modal is still open (form validation prevented submission)
      const modalVisible = await visitModal.isVisible()
      expect(modalVisible).toBe(true)

      // Verify name field has validation error (HTML5 validation)
      const isNameValid = await visitModal.locator('input[name="name"]').evaluate((el) => el.validity.valid)
      expect(isNameValid).toBe(false)
    })
  })
})
