import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js'

test.describe('Map Performance', () => {
  test('map loads within acceptable time', async ({ page }) => {
    const startTime = Date.now()

    await page.goto('/maps/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)

    const loadTime = Date.now() - startTime
    console.log(`Map loaded in ${loadTime}ms`)

    // Should load in less than 15 seconds (including modal, map init, data fetch)
    expect(loadTime).toBeLessThan(15000)
  })

  test('handles large datasets efficiently', async ({ page }) => {
    await page.goto('/maps/v2?start_at=2025-10-01T00:00&end_at=2025-10-31T23:59')
    await closeOnboardingModal(page)

    const startTime = Date.now()
    await waitForLoadingComplete(page)
    const loadTime = Date.now() - startTime

    console.log(`Large dataset loaded in ${loadTime}ms`)

    // Should still complete reasonably quickly
    expect(loadTime).toBeLessThan(15000)
  })
})
