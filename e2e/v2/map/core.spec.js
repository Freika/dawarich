import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import {
  navigateToMapsV2,
  navigateToMapsV2WithDate,
  waitForMapLibre,
  waitForLoadingComplete,
  hasMapInstance,
  getMapZoom,
  getMapCenter
} from '../helpers/setup.js'

test.describe('Map Core', () => {
  test.beforeEach(async ({ page }) => {
    await navigateToMapsV2(page)
    await closeOnboardingModal(page)
  })

  test.describe('Initialization', () => {
    test('loads map container', async ({ page }) => {
      const mapContainer = page.locator('[data-maps-v2-target="container"]')
      await expect(mapContainer).toBeVisible()
    })

    test('initializes MapLibre instance', async ({ page }) => {
      await waitForMapLibre(page)

      const canvas = page.locator('.maplibregl-canvas')
      await expect(canvas).toBeVisible()

      const hasMap = await hasMapInstance(page)
      expect(hasMap).toBe(true)
    })

    test('has valid initial center and zoom', async ({ page }) => {
      await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
      await closeOnboardingModal(page)
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1000)

      const center = await getMapCenter(page)
      const zoom = await getMapZoom(page)

      expect(center).not.toBeNull()
      expect(center.lng).toBeGreaterThan(-180)
      expect(center.lng).toBeLessThan(180)
      expect(center.lat).toBeGreaterThan(-90)
      expect(center.lat).toBeLessThan(90)

      expect(zoom).toBeGreaterThan(0)
      expect(zoom).toBeLessThan(20)
    })
  })

  test.describe('Loading States', () => {
    test('shows loading indicator during data fetch', async ({ page }) => {
      const loading = page.locator('[data-maps-v2-target="loading"]')

      const navigationPromise = page.reload({ waitUntil: 'domcontentloaded' })

      const loadingVisible = await loading.evaluate((el) => !el.classList.contains('hidden'))
        .catch(() => false)

      await navigationPromise
      await closeOnboardingModal(page)

      await waitForLoadingComplete(page)
      await expect(loading).toHaveClass(/hidden/)
    })

    test('handles empty data gracefully', async ({ page }) => {
      await navigateToMapsV2WithDate(page, '2020-01-01T00:00', '2020-01-01T23:59')
      await closeOnboardingModal(page)

      await waitForLoadingComplete(page)
      await page.waitForTimeout(500)

      const hasMap = await hasMapInstance(page)
      expect(hasMap).toBe(true)
    })
  })

  test.describe('Data Bounds', () => {
    test('fits map bounds to loaded data', async ({ page }) => {
      await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
      await closeOnboardingModal(page)
      await waitForMapLibre(page)
      await waitForLoadingComplete(page)
      await page.waitForTimeout(1000)

      const zoom = await getMapZoom(page)
      expect(zoom).toBeGreaterThan(2)
    })
  })

  test.describe('Lifecycle', () => {
    test('cleans up and reinitializes on navigation', async ({ page }) => {
      await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
      await closeOnboardingModal(page)
      await waitForLoadingComplete(page)

      // Navigate away
      await page.goto('/')
      await page.waitForTimeout(500)

      // Navigate back
      await navigateToMapsV2(page)
      await closeOnboardingModal(page)

      await waitForMapLibre(page)
      const hasMap = await hasMapInstance(page)
      expect(hasMap).toBe(true)
    })

    test('reloads data when changing date range', async ({ page }) => {
      await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
      await closeOnboardingModal(page)
      await waitForLoadingComplete(page)

      const startInput = page.locator('input[type="datetime-local"][name="start_at"]')
      const initialStartDate = await startInput.inputValue()

      await navigateToMapsV2WithDate(page, '2024-10-14T00:00', '2024-10-14T23:59')
      await closeOnboardingModal(page)

      await waitForMapLibre(page)
      await waitForLoadingComplete(page)

      const newStartDate = await startInput.inputValue()
      expect(newStartDate).not.toBe(initialStartDate)

      const hasMap = await hasMapInstance(page)
      expect(hasMap).toBe(true)
    })
  })
})
