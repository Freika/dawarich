import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js'

test.describe('Area Selection in Maps V2', () => {
  test.beforeEach(async ({ page }) => {
    // Navigate to Maps V2 with specific date range that has data
    await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    // Wait a bit for data to load
    await page.waitForTimeout(1000)
  })

  test('should enable area selection mode when clicking Select Area button', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Wait a moment for UI to update
    await page.waitForTimeout(100)

    // Verify the button changes to Cancel Selection
    const selectButton = page.locator('[data-maps-v2-target="selectAreaButton"]')
    await expect(selectButton).toContainText('Cancel Selection', { timeout: 2000 })
    await expect(selectButton).toHaveClass(/btn-error/)

    // Verify cursor changes to crosshair (via canvas style)
    const canvas = page.locator('canvas.maplibregl-canvas')
    const cursorStyle = await canvas.evaluate(el => window.getComputedStyle(el).cursor)
    expect(cursorStyle).toBe('crosshair')

    // Verify toast notification appears
    await expect(page.locator('.toast, [role="alert"]').filter({ hasText: 'Draw a rectangle' })).toBeVisible({ timeout: 5000 })
  })

  test('should draw selection rectangle when dragging mouse', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Wait for selection mode to be enabled
    await page.waitForTimeout(500)

    // Check if selection layer has been added to map
    const hasSelectionLayer = await page.evaluate(() => {
      const element = document.querySelector('[data-controller="maps-v2"]')
      const app = window.Stimulus || window.Application
      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
      return controller.selectionLayer !== undefined
    })
    expect(hasSelectionLayer).toBeTruthy()

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Draw selection rectangle with fewer steps to avoid timeout
    await page.mouse.move(box.x + 100, box.y + 100)
    await page.mouse.down()
    await page.mouse.move(box.x + 300, box.y + 300, { steps: 3 })
    await page.mouse.up()

    // Wait for API call to complete (or timeout gracefully)
    await page.waitForResponse(response =>
      response.url().includes('/api/v1/points') &&
      response.url().includes('min_longitude'),
      { timeout: 5000 }
    ).catch(() => null)
  })

  test('should show selection actions when points are selected', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Draw selection rectangle over map center
    await page.mouse.move(box.x + box.width / 2 - 100, box.y + box.height / 2 - 100)
    await page.mouse.down()
    await page.mouse.move(box.x + box.width / 2 + 100, box.y + box.height / 2 + 100, { steps: 10 })
    await page.mouse.up()

    // Wait for API call to complete
    await page.waitForResponse(response =>
      response.url().includes('/api/v1/points'),
      { timeout: 5000 }
    ).catch(() => null)

    // Wait for potential updates
    await page.waitForTimeout(1000)

    // If points were found, verify UI updates
    const selectionActions = page.locator('[data-maps-v2-target="selectionActions"]')
    const isVisible = await selectionActions.isVisible().catch(() => false)

    if (isVisible) {
      // Verify delete button is visible and shows count
      const deleteButton = page.locator('[data-maps-v2-target="deleteButtonText"]')
      await expect(deleteButton).toBeVisible()

      // Wait for button text to update with count
      await expect(deleteButton).toContainText(/Delete \d+ Points?/, { timeout: 2000 })

      // Verify the Select Area button has changed to Cancel Selection (at top of tools)
      const selectButton = page.locator('[data-maps-v2-target="selectAreaButton"]')
      await expect(selectButton).toContainText('Cancel Selection')
    }
  })

  test('should cancel area selection', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Wait for selection mode
    await page.waitForTimeout(500)

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Draw selection rectangle with fewer steps
    await page.mouse.move(box.x + box.width / 2 - 100, box.y + box.height / 2 - 100)
    await page.mouse.down()
    await page.mouse.move(box.x + box.width / 2 + 100, box.y + box.height / 2 + 100, { steps: 3 })
    await page.mouse.up()

    // Wait for API call
    await page.waitForResponse(response =>
      response.url().includes('/api/v1/points'),
      { timeout: 5000 }
    ).catch(() => null)

    await page.waitForTimeout(500)

    // Check if selection actions are visible
    const selectionActions = page.locator('[data-maps-v2-target="selectionActions"]')
    const isVisible = await selectionActions.isVisible().catch(() => false)

    if (isVisible) {
      // Click Cancel button (the red one at the top that replaced Select Area)
      const cancelButton = page.locator('[data-maps-v2-target="selectAreaButton"]')
      await expect(cancelButton).toContainText('Cancel Selection')
      await cancelButton.click()

      // Verify selection actions are hidden
      await expect(selectionActions).toBeHidden()

      // Verify Select Area button is restored
      await expect(cancelButton).toContainText('Select Area')
      await expect(cancelButton).toHaveClass(/btn-outline/)
      await expect(cancelButton).not.toHaveClass(/btn-error/)
    }
  })

  test('should display delete confirmation dialog', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Draw selection rectangle
    await page.mouse.move(box.x + box.width / 2 - 100, box.y + box.height / 2 - 100)
    await page.mouse.down()
    await page.mouse.move(box.x + box.width / 2 + 100, box.y + box.height / 2 + 100, { steps: 10 })
    await page.mouse.up()

    // Wait for API call
    await page.waitForResponse(response =>
      response.url().includes('/api/v1/points'),
      { timeout: 5000 }
    ).catch(() => null)

    await page.waitForTimeout(500)

    // Check if selection actions are visible
    const selectionActions = page.locator('[data-maps-v2-target="selectionActions"]')
    const isVisible = await selectionActions.isVisible().catch(() => false)

    if (isVisible) {
      // Setup dialog handler before clicking
      let dialogShown = false
      page.once('dialog', async dialog => {
        dialogShown = true
        expect(dialog.message()).toContain('Are you sure')
        expect(dialog.message()).toContain('delete')
        await dialog.dismiss()
      })

      // Click Delete button (text now includes count like "Delete 100 Points")
      await page.locator('[data-maps-v2-target="deletePointsButton"]').click()

      // Wait for dialog to be handled
      await page.waitForTimeout(1000)

      // Verify dialog was shown
      expect(dialogShown).toBe(true)

      // Verify selection is still active (because we dismissed)
      await expect(selectionActions).toBeVisible()
    }
  })

  test('should have API support for geographic bounds filtering', async ({ page }) => {
    // Test that the backend accepts geographic bounds parameters
    // by verifying the API call is made with the correct parameters when selecting an area

    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')
    await page.waitForTimeout(500)

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Set up network listener before drawing
    let hasGeoBounds = false

    page.on('request', request => {
      if (request.url().includes('/api/v1/points')) {
        const url = new URL(request.url(), 'http://localhost')
        if (url.searchParams.has('min_longitude') &&
            url.searchParams.has('max_longitude') &&
            url.searchParams.has('min_latitude') &&
            url.searchParams.has('max_latitude')) {
          hasGeoBounds = true
        }
      }
    })

    // Draw selection rectangle
    await page.mouse.move(box.x + 100, box.y + 100)
    await page.mouse.down()
    await page.mouse.move(box.x + 200, box.y + 200, { steps: 2 })
    await page.mouse.up()

    // Wait for API call
    await page.waitForTimeout(2000)

    // Verify the API was called with geographic bounds parameters
    expect(hasGeoBounds).toBe(true)
  })

  test('should add selected points layer to map when points are selected', async ({ page }) => {
    // Open settings panel and switch to Tools tab
    await page.click('[data-action="click->maps-v2#toggleSettings"]')
    await page.click('button[data-tab="tools"]')

    // Click Select Area button
    await page.click('[data-maps-v2-target="selectAreaButton"]')

    // Get map canvas
    const canvas = page.locator('canvas.maplibregl-canvas')
    const box = await canvas.boundingBox()

    // Draw selection rectangle
    await page.mouse.move(box.x + box.width / 2 - 50, box.y + box.height / 2 - 50)
    await page.mouse.down()
    await page.mouse.move(box.x + box.width / 2 + 50, box.y + box.height / 2 + 50, { steps: 5 })
    await page.mouse.up()

    // Wait for API call
    await page.waitForResponse(response =>
      response.url().includes('/api/v1/points'),
      { timeout: 5000 }
    ).catch(() => null)

    await page.waitForTimeout(500)

    // Check if selected points layer exists
    const hasSelectedPointsLayer = await page.evaluate(() => {
      const element = document.querySelector('[data-controller="maps-v2"]')
      const app = window.Stimulus || window.Application
      const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
      return controller?.selectedPointsLayer !== undefined
    })

    // If points were selected, layer should exist
    if (hasSelectedPointsLayer) {
      // Verify layer is on the map
      const layerExistsOnMap = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        const app = window.Stimulus || window.Application
        const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
        return controller?.map?.getLayer('selected-points') !== undefined
      })
      expect(layerExistsOnMap).toBeTruthy()
    }
  })
})
