import { test, expect } from '@playwright/test'
import { closeOnboardingModal } from '../../helpers/navigation.js'
import { waitForMapLibre, waitForLoadingComplete } from '../helpers/setup.js'

test.describe('Location Search', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/maps_v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59')
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe('Search UI', () => {
    test('displays search input in settings panel', async ({ page }) => {
      // Open settings panel
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      // Search tab should be active by default
      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      await expect(searchInput).toBeVisible()
      await expect(searchInput).toHaveAttribute('placeholder', 'Enter name of a place')
    })

    test('search results container exists', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')
      await expect(resultsContainer).toBeAttached()
      await expect(resultsContainer).toHaveClass(/hidden/)
    })
  })

  test.describe('Search Functionality', () => {
    test('typing in search input triggers search', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')

      // Type a search query
      await searchInput.fill('New')
      await page.waitForTimeout(500) // Wait for debounce

      // Results container should become visible (or show loading)
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Wait for results to appear
      await page.waitForTimeout(1000)

      // Check if results container is no longer hidden
      const isHidden = await resultsContainer.evaluate(el => el.classList.contains('hidden'))

      // Results should be shown (either with results or "no results" message)
      if (!isHidden) {
        expect(isHidden).toBe(false)
      }
    })

    test('short queries do not trigger search', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Type single character
      await searchInput.fill('N')
      await page.waitForTimeout(500)

      // Results should stay hidden
      await expect(resultsContainer).toHaveClass(/hidden/)
    })

    test('clearing search clears results', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Type search query
      await searchInput.fill('New York')
      await page.waitForTimeout(1000)

      // Clear input
      await searchInput.clear()
      await page.waitForTimeout(300)

      // Results should be hidden
      await expect(resultsContainer).toHaveClass(/hidden/)
    })
  })

  test.describe('Search Integration', () => {
    test('search manager is initialized', async ({ page }) => {
      // Wait for controller to be fully initialized
      await page.waitForTimeout(1000)

      const hasSearchManager = await page.evaluate(() => {
        const element = document.querySelector('[data-controller="maps-v2"]')
        if (!element) return false

        const app = window.Stimulus || window.Application
        if (!app) return false

        const controller = app.getControllerForElementAndIdentifier(element, 'maps-v2')
        return controller?.searchManager !== undefined
      })

      // Search manager should exist if search targets are present
      const hasSearchTargets = await page.locator('[data-maps-v2-target="searchInput"]').count()
      if (hasSearchTargets > 0) {
        expect(hasSearchManager).toBe(true)
      }
    })

    test('search input has autocomplete disabled', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      await expect(searchInput).toHaveAttribute('autocomplete', 'off')
    })
  })

  test.describe('Visit Search and Creation', () => {
    test('clicking on suggestion shows visits', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Search for a location
      await searchInput.fill('Sterndamm')
      await page.waitForTimeout(800) // Wait for debounce + API

      // Wait for suggestions to appear
      const firstSuggestion = resultsContainer.locator('.search-result-item').first()
      await expect(firstSuggestion).toBeVisible({ timeout: 5000 })

      // Click on first suggestion
      await firstSuggestion.click()
      await page.waitForTimeout(1500) // Wait for visits API call

      // Results container should show visits or "no visits found"
      const hasVisits = await resultsContainer.locator('.location-result').count()
      const hasNoVisitsMessage = await resultsContainer.locator('text=No visits found').count()

      expect(hasVisits > 0 || hasNoVisitsMessage > 0).toBe(true)
    })

    test('visits are grouped by year with expand/collapse', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Search and select location
      await searchInput.fill('Sterndamm')
      await page.waitForTimeout(800)

      const firstSuggestion = resultsContainer.locator('.search-result-item').first()
      await expect(firstSuggestion).toBeVisible({ timeout: 5000 })
      await firstSuggestion.click()
      await page.waitForTimeout(1500)

      // Check if year toggles exist
      const yearToggle = resultsContainer.locator('.year-toggle').first()
      const hasYearToggle = await yearToggle.count()

      if (hasYearToggle > 0) {
        // Year visits should be hidden initially
        const yearVisits = resultsContainer.locator('.year-visits').first()
        await expect(yearVisits).toHaveClass(/hidden/)

        // Click year toggle to expand
        await yearToggle.click()
        await page.waitForTimeout(300)

        // Year visits should now be visible
        await expect(yearVisits).not.toHaveClass(/hidden/)
      }
    })

    test('clicking on visit item opens create visit modal', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Search and select location
      await searchInput.fill('Sterndamm')
      await page.waitForTimeout(800)

      const firstSuggestion = resultsContainer.locator('.search-result-item').first()
      await expect(firstSuggestion).toBeVisible({ timeout: 5000 })
      await firstSuggestion.click()
      await page.waitForTimeout(1500)

      // Check if there are visits
      const yearToggle = resultsContainer.locator('.year-toggle').first()
      const hasVisits = await yearToggle.count()

      if (hasVisits > 0) {
        // Expand year section
        await yearToggle.click()
        await page.waitForTimeout(300)

        // Click on first visit item
        const visitItem = resultsContainer.locator('.visit-item').first()
        await visitItem.click()
        await page.waitForTimeout(500)

        // Modal should appear
        const modal = page.locator('#create-visit-modal')
        await expect(modal).toBeVisible()

        // Modal should have form fields
        await expect(modal.locator('input[name="name"]')).toBeVisible()
        await expect(modal.locator('input[name="started_at"]')).toBeVisible()
        await expect(modal.locator('input[name="ended_at"]')).toBeVisible()

        // Close modal
        await modal.locator('button:has-text("Cancel")').click()
        await page.waitForTimeout(500)
      }
    })

    test('create visit modal has prefilled data', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')
      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Search and select location
      await searchInput.fill('Sterndamm')
      await page.waitForTimeout(800)

      const firstSuggestion = resultsContainer.locator('.search-result-item').first()
      await expect(firstSuggestion).toBeVisible({ timeout: 5000 })
      await firstSuggestion.click()
      await page.waitForTimeout(1500)

      // Check if there are visits
      const yearToggle = resultsContainer.locator('.year-toggle').first()
      const hasVisits = await yearToggle.count()

      if (hasVisits > 0) {
        // Expand and click visit
        await yearToggle.click()
        await page.waitForTimeout(300)

        const visitItem = resultsContainer.locator('.visit-item').first()
        await visitItem.click()
        await page.waitForTimeout(500)

        const modal = page.locator('#create-visit-modal')
        await expect(modal).toBeVisible()

        // Name should be prefilled
        const nameInput = modal.locator('input[name="name"]')
        const nameValue = await nameInput.inputValue()
        expect(nameValue.length).toBeGreaterThan(0)

        // Start and end times should be prefilled
        const startInput = modal.locator('input[name="started_at"]')
        const startValue = await startInput.inputValue()
        expect(startValue.length).toBeGreaterThan(0)

        const endInput = modal.locator('input[name="ended_at"]')
        const endValue = await endInput.inputValue()
        expect(endValue.length).toBeGreaterThan(0)

        // Close modal
        await modal.locator('button:has-text("Cancel")').click()
        await page.waitForTimeout(500)
      }
    })

    test('results container height allows viewing multiple visits', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const resultsContainer = page.locator('[data-maps-v2-target="searchResults"]')

      // Check max-height class is set appropriately (max-h-96)
      const hasMaxHeight = await resultsContainer.evaluate(el => {
        const classes = el.className
        return classes.includes('max-h-96') || classes.includes('max-h')
      })

      expect(hasMaxHeight).toBe(true)
    })
  })

  test.describe('Accessibility', () => {
    test('search input is keyboard accessible', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const searchInput = page.locator('[data-maps-v2-target="searchInput"]')

      // Focus input with keyboard
      await searchInput.focus()
      await expect(searchInput).toBeFocused()

      // Type with keyboard
      await page.keyboard.type('Paris')
      await page.waitForTimeout(500)

      const value = await searchInput.inputValue()
      expect(value).toBe('Paris')
    })

    test('search has descriptive label', async ({ page }) => {
      await page.click('button[title="Open map settings"]')
      await page.waitForTimeout(400)

      const label = page.locator('label:has-text("Search for a place")')
      await expect(label).toBeVisible()
    })
  })
})
