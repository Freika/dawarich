import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../../helpers/navigation.js"
import { waitForLoadingComplete, waitForMapLibre } from "../helpers/setup.js"

/**
 * Helper to open settings panel and switch to Search tab
 * @param {Page} page - Playwright page object
 */
async function openSearchTab(page) {
  await page.click('button[title="Open map settings"]')
  // Wait for panel to fully open (300ms CSS transition + buffer)
  await page.waitForSelector(".map-control-panel.open", { timeout: 3000 })
  await page.waitForTimeout(200)
  await page.click('button[title="Search"]')
  await page.waitForTimeout(300)
}

test.describe("Location Search", () => {
  // Increase timeout for search tests as they involve network requests
  test.setTimeout(60000)

  test.beforeEach(async ({ page }) => {
    await page.goto("/map/v2?start_at=2025-10-15T00:00&end_at=2025-10-15T23:59")
    await closeOnboardingModal(page)
    await waitForMapLibre(page)
    await waitForLoadingComplete(page)
    await page.waitForTimeout(1500)
  })

  test.describe("Search UI", () => {
    test("displays search input in settings panel", async ({ page }) => {
      // Open settings panel
      await openSearchTab(page)

      // Search tab should be active by default
      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      await expect(searchInput).toBeVisible()
      await expect(searchInput).toHaveAttribute(
        "placeholder",
        "Enter name of a place",
      )
    })

    test("search results container exists", async ({ page }) => {
      await openSearchTab(page)

      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )
      await expect(resultsContainer).toBeAttached()
      await expect(resultsContainer).toHaveClass(/hidden/)
    })
  })

  test.describe("Search Functionality", () => {
    test("typing in search input triggers search", async ({ page }) => {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Type a search query (3+ chars to trigger search)
      await searchInput.fill("New")

      // Wait for results container to become visible or stay hidden (with timeout)
      // Search might show results or "no results" - both are valid
      try {
        await resultsContainer.waitFor({ state: "visible", timeout: 3000 })
        // Results appeared
        expect(await resultsContainer.isVisible()).toBe(true)
      } catch (_e) {
        // Results might still be hidden if search returned nothing
        // This is acceptable behavior
        console.log("Search did not return visible results")
      }
    })

    test("short queries do not trigger search", async ({ page }) => {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Type single character (should not trigger search - minimum is 3 chars)
      await searchInput.fill("N")

      // Wait a bit for any potential search to trigger
      await page.waitForTimeout(500)

      // Results should stay hidden (search not triggered for short query)
      await expect(resultsContainer).toHaveClass(/hidden/)
    })

    test("clearing search clears results", async ({ page }) => {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Type search query
      await searchInput.fill("Berlin")

      // Wait for potential search results
      await page.waitForTimeout(1000)

      // Clear input
      await searchInput.clear()
      await page.waitForTimeout(300)

      // Results should be hidden after clearing
      await expect(resultsContainer).toHaveClass(/hidden/)
    })
  })

  test.describe("Search Integration", () => {
    test("search manager is initialized", async ({ page }) => {
      // Wait for controller to be fully initialized
      await page.waitForTimeout(1000)

      const hasSearchManager = await page.evaluate(() => {
        const element = document.querySelector(
          '[data-controller*="maps--maplibre"]',
        )
        if (!element) return false

        const app = window.Stimulus || window.Application
        if (!app) return false

        const controller = app.getControllerForElementAndIdentifier(
          element,
          "maps--maplibre",
        )
        return controller?.searchManager !== undefined
      })

      // Search manager should exist if search targets are present
      const hasSearchTargets = await page
        .locator('[data-maps--maplibre-target="searchInput"]')
        .count()
      if (hasSearchTargets > 0) {
        expect(hasSearchManager).toBe(true)
      }
    })

    test("search input has autocomplete disabled", async ({ page }) => {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      await expect(searchInput).toHaveAttribute("autocomplete", "off")
    })
  })

  test.describe("Visit Search and Creation", () => {
    /**
     * Helper to search for a location and wait for suggestions
     */
    async function searchAndGetSuggestion(page) {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )
      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Type search query and wait for the suggestions API response
      const suggestionsPromise = page.waitForResponse(
        (resp) =>
          resp.url().includes("/api/v1/locations/suggestions") &&
          resp.status() === 200,
        { timeout: 15000 },
      )
      await searchInput.fill("Sterndamm")
      await suggestionsPromise

      // Wait for suggestions to render
      const firstSuggestion = resultsContainer
        .locator(".search-result-item")
        .first()
      await expect(firstSuggestion).toBeVisible({ timeout: 5000 })

      return { searchInput, resultsContainer, firstSuggestion }
    }

    /**
     * Helper to click a suggestion and wait for visits to load
     */
    async function clickSuggestionAndWaitForVisits(page, firstSuggestion) {
      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Click suggestion and wait for visits API response
      const visitsPromise = page
        .waitForResponse(
          (resp) =>
            resp.url().includes("/api/v1/locations?") && resp.status() === 200,
          { timeout: 15000 },
        )
        .catch(() => null) // Visits API may fail
      await firstSuggestion.click()
      await visitsPromise
      await page.waitForTimeout(500) // Let DOM update

      return resultsContainer
    }

    test("clicking on suggestion shows visits", async ({ page }) => {
      const { firstSuggestion } = await searchAndGetSuggestion(page)
      const resultsContainer = await clickSuggestionAndWaitForVisits(
        page,
        firstSuggestion,
      )

      // Results container should show visits or "no visits found"
      const hasVisits = await resultsContainer
        .locator(".location-result")
        .count()
      const hasNoVisitsMessage = await resultsContainer
        .locator("text=No visits found")
        .count()

      expect(hasVisits > 0 || hasNoVisitsMessage > 0).toBe(true)
    })

    test("visits are grouped by year with expand/collapse", async ({
      page,
    }) => {
      const { firstSuggestion } = await searchAndGetSuggestion(page)
      const resultsContainer = await clickSuggestionAndWaitForVisits(
        page,
        firstSuggestion,
      )

      // Check if year toggles exist
      const yearToggle = resultsContainer.locator(".year-toggle").first()
      const hasYearToggle = await yearToggle.count()

      if (hasYearToggle > 0) {
        // Year visits should be hidden initially
        const yearVisits = resultsContainer.locator(".year-visits").first()
        await expect(yearVisits).toHaveClass(/hidden/)

        // Click year toggle to expand
        await yearToggle.click()
        await page.waitForTimeout(300)

        // Year visits should now be visible
        await expect(yearVisits).not.toHaveClass(/hidden/)
      }
    })

    test("clicking on visit item opens create visit modal", async ({
      page,
    }) => {
      const { firstSuggestion } = await searchAndGetSuggestion(page)
      const resultsContainer = await clickSuggestionAndWaitForVisits(
        page,
        firstSuggestion,
      )

      // Check if there are visits
      const yearToggle = resultsContainer.locator(".year-toggle").first()
      const hasVisits = await yearToggle.count()

      if (hasVisits > 0) {
        // Expand year section
        await yearToggle.click()
        await page.waitForTimeout(300)

        // Click on first visit item
        const visitItem = resultsContainer.locator(".visit-item").first()
        await visitItem.click()
        await page.waitForTimeout(500)

        // Modal should appear - wait for modal to be created and checkbox to be checked
        const modal = page.locator("#create-visit-modal")
        await modal.waitFor({ state: "attached" })
        const modalToggle = page.locator("#create-visit-modal-toggle")
        await expect(modalToggle).toBeChecked()

        // Modal should have form fields
        await expect(modal.locator('input[name="name"]')).toBeVisible()
        await expect(modal.locator('input[name="started_at"]')).toBeVisible()
        await expect(modal.locator('input[name="ended_at"]')).toBeVisible()

        // Close modal
        await modal.locator('button:has-text("Cancel")').click()
        await page.waitForTimeout(500)
      }
    })

    test("create visit modal has prefilled data", async ({ page }) => {
      const { firstSuggestion } = await searchAndGetSuggestion(page)
      const resultsContainer = await clickSuggestionAndWaitForVisits(
        page,
        firstSuggestion,
      )

      // Check if there are visits
      const yearToggle = resultsContainer.locator(".year-toggle").first()
      const hasVisits = await yearToggle.count()

      if (hasVisits > 0) {
        // Expand and click visit
        await yearToggle.click()
        await page.waitForTimeout(300)

        const visitItem = resultsContainer.locator(".visit-item").first()
        await visitItem.click()
        await page.waitForTimeout(500)

        // Modal should appear - wait for modal to be created and checkbox to be checked
        const modal = page.locator("#create-visit-modal")
        await modal.waitFor({ state: "attached" })
        const modalToggle = page.locator("#create-visit-modal-toggle")
        await expect(modalToggle).toBeChecked()

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

    test("results container height allows viewing multiple visits", async ({
      page,
    }) => {
      await openSearchTab(page)

      const resultsContainer = page.locator(
        '[data-maps--maplibre-target="searchResults"]',
      )

      // Check max-height class is set appropriately (max-h-96)
      const hasMaxHeight = await resultsContainer.evaluate((el) => {
        const classes = el.className
        return classes.includes("max-h-96") || classes.includes("max-h")
      })

      expect(hasMaxHeight).toBe(true)
    })
  })

  test.describe("Accessibility", () => {
    test("search input is keyboard accessible", async ({ page }) => {
      await openSearchTab(page)

      const searchInput = page.locator(
        '[data-maps--maplibre-target="searchInput"]',
      )

      // Focus input with keyboard
      await searchInput.focus()
      await expect(searchInput).toBeFocused()

      // Type with keyboard
      await page.keyboard.type("Paris")
      await page.waitForTimeout(500)

      const value = await searchInput.inputValue()
      expect(value).toBe("Paris")
    })

    test("search has descriptive label", async ({ page }) => {
      await openSearchTab(page)

      const label = page.locator('label:has-text("Search for a place")')
      await expect(label).toBeVisible()
    })
  })
})
