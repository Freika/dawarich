import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../../helpers/navigation.js'
import {
  navigateToMapsV2WithDate,
  waitForLoadingComplete,
  hasLayer,
  getPointsSourceData
} from '../../helpers/setup.js'

test.describe('Points Layer', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Display', () => {
    test('displays points layer', async ({ page }) => {
      // Wait for points layer to be added
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getLayer('points') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const hasPoints = await hasLayer(page, 'points')
      expect(hasPoints).toBe(true)
    })

    test('loads and displays point data', async ({ page }) => {
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('points-source') !== undefined
      }, { timeout: 15000 }).catch(() => false)

      const sourceData = await getPointsSourceData(page)
      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.featureCount).toBeGreaterThan(0)
    })
  })

  test.describe('Data Source', () => {
    test('points source contains valid GeoJSON features', async ({ page }) => {
      // Wait for source to be added
      await page.waitForFunction(() => {
        const element = document.querySelector('[data-controller*="maps--maplibre"]')
        const app = window.Stimulus || window.Application
        const controller = app?.getControllerForElementAndIdentifier(element, 'maps--maplibre')
        return controller?.map?.getSource('points-source') !== undefined
      }, { timeout: 10000 }).catch(() => false)

      const sourceData = await getPointsSourceData(page)

      expect(sourceData.hasSource).toBe(true)
      expect(sourceData.features).toBeDefined()
      expect(Array.isArray(sourceData.features)).toBe(true)

      if (sourceData.features.length > 0) {
        const firstFeature = sourceData.features[0]
        expect(firstFeature.type).toBe('Feature')
        expect(firstFeature.geometry).toBeDefined()
        expect(firstFeature.geometry.type).toBe('Point')
        expect(firstFeature.geometry.coordinates).toHaveLength(2)
      }
    })
  })
})
