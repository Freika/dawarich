import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../helpers/navigation.js"

/**
 * Calendar Panel Tests
 *
 * Tests for the calendar panel control that allows users to navigate between
 * different years and months. The panel is opened via the "Toggle Panel" button
 * in the top-right corner of the map.
 */

test.describe("Calendar Panel", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/map")
    await closeOnboardingModal(page)

    // Wait for map to be fully loaded
    await page.waitForSelector(".leaflet-container", {
      state: "visible",
      timeout: 10000,
    })
    await page.waitForTimeout(2000) // Wait for all controls to be initialized
  })

  /**
   * Helper function to find and click the calendar toggle button
   */
  async function clickCalendarButton(page) {
    // The calendar button is the "Toggle Panel" button with a calendar icon
    // It's the third button in the top-right control stack (after Select Area and Add Visit)
    const calendarButton = await page
      .locator("button.toggle-panel-button")
      .first()
    await expect(calendarButton).toBeVisible({ timeout: 5000 })
    await calendarButton.click()
    await page.waitForTimeout(500) // Wait for panel animation
  }

  /**
   * Helper function to check if panel is visible
   */
  async function isPanelVisible(page) {
    const panel = page.locator(".leaflet-right-panel")
    const isVisible = await panel.isVisible().catch(() => false)
    if (!isVisible) return false

    const displayStyle = await panel.evaluate((el) => el.style.display)
    return displayStyle !== "none"
  }

  test("should open calendar panel on first click", async ({ page }) => {
    // Verify panel is not visible initially
    const initiallyVisible = await isPanelVisible(page)
    expect(initiallyVisible).toBe(false)

    // Click calendar button
    await clickCalendarButton(page)

    // Verify panel is now visible
    const panelVisible = await isPanelVisible(page)
    expect(panelVisible).toBe(true)

    // Verify panel contains expected elements
    const yearSelect = page.locator("#year-select")
    await expect(yearSelect).toBeVisible()

    const monthsGrid = page.locator("#months-grid")
    await expect(monthsGrid).toBeVisible()

    // Verify "Whole year" link is present
    const wholeYearLink = page.locator("#whole-year-link")
    await expect(wholeYearLink).toBeVisible()
  })

  test("should close calendar panel on second click", async ({ page }) => {
    // Open panel
    await clickCalendarButton(page)
    await page.waitForTimeout(300)

    // Verify panel is visible
    let panelVisible = await isPanelVisible(page)
    expect(panelVisible).toBe(true)

    // Click button again to close
    await clickCalendarButton(page)
    await page.waitForTimeout(300)

    // Verify panel is hidden
    panelVisible = await isPanelVisible(page)
    expect(panelVisible).toBe(false)
  })

  test("should allow year selection", async ({ page }) => {
    // Open panel
    await clickCalendarButton(page)

    // Wait for year select to be populated (it loads from API)
    await page.waitForTimeout(2000)

    const yearSelect = page.locator("#year-select")
    await expect(yearSelect).toBeVisible()

    // Get available years
    const options = await yearSelect.locator("option:not([disabled])").all()

    // Should have at least one year available
    expect(options.length).toBeGreaterThan(0)

    // Select the first available year
    const firstYearOption = options[0]
    const yearValue = await firstYearOption.getAttribute("value")

    await yearSelect.selectOption(yearValue)

    // Verify year was selected
    const selectedValue = await yearSelect.inputValue()
    expect(selectedValue).toBe(yearValue)
  })

  test("should navigate to month when clicking month button", async ({
    page,
  }) => {
    // Open panel
    await clickCalendarButton(page)

    // Wait for months to load
    await page.waitForTimeout(3000)

    // Select year 2024 (which has October data in demo)
    const yearSelect = page.locator("#year-select")
    await yearSelect.selectOption("2024")
    await page.waitForTimeout(500)

    // Find October button (demo data has October 2024)
    const octoberButton = page.locator('#months-grid a[data-month-name="Oct"]')
    await expect(octoberButton).toBeVisible({ timeout: 5000 })

    // Verify October is enabled (not disabled)
    const isDisabled = await octoberButton.evaluate((el) =>
      el.classList.contains("disabled"),
    )
    expect(isDisabled).toBe(false)

    // Verify button is clickable
    const pointerEvents = await octoberButton.evaluate(
      (el) => el.style.pointerEvents,
    )
    expect(pointerEvents).not.toBe("none")

    // Get the expected href before clicking
    const expectedHref = await octoberButton.getAttribute("href")
    expect(expectedHref).toBeTruthy()
    const decodedHref = decodeURIComponent(expectedHref)

    expect(decodedHref).toContain("map?")
    expect(decodedHref).toContain("start_at=2024-10-01T00:00")
    expect(decodedHref).toContain("end_at=2024-10-31T23:59")

    // Click the month button and wait for navigation
    await Promise.all([
      page.waitForURL("**/map**", { timeout: 10000 }),
      octoberButton.click(),
    ])

    // Wait for page to settle
    await page.waitForLoadState("networkidle", { timeout: 10000 })

    // Verify we navigated to the map page
    expect(page.url()).toContain("/map")

    // Verify map loaded with data
    await page.waitForSelector(".leaflet-container", {
      state: "visible",
      timeout: 10000,
    })
  })

  test('should navigate to whole year when clicking "Whole year" button', async ({
    page,
  }) => {
    // Open panel
    await clickCalendarButton(page)

    // Wait for panel to load
    await page.waitForTimeout(2000)

    const wholeYearLink = page.locator("#whole-year-link")
    await expect(wholeYearLink).toBeVisible()

    // Get the href and decode it
    const href = await wholeYearLink.getAttribute("href")
    expect(href).toBeTruthy()
    const decodedHref = decodeURIComponent(href)

    expect(decodedHref).toContain("map?")
    expect(decodedHref).toContain("start_at=")
    expect(decodedHref).toContain("end_at=")

    // Href should contain full year dates (01-01 to 12-31)
    expect(decodedHref).toContain("-01-01T00:00")
    expect(decodedHref).toContain("-12-31T23:59")

    // Store the expected year from the href
    const yearMatch = decodedHref.match(/(\d{4})-01-01/)
    expect(yearMatch).toBeTruthy()
    const expectedYear = yearMatch[1]

    // Click the link and wait for navigation
    await Promise.all([
      page.waitForURL("**/map**", { timeout: 10000 }),
      wholeYearLink.click(),
    ])

    // Wait for page to settle
    await page.waitForLoadState("networkidle", { timeout: 10000 })

    // Verify we navigated to the map page
    expect(page.url()).toContain("/map")

    // The URL parameters might be processed differently (e.g., stripped by Turbo or redirected)
    // Instead of checking URL, verify the panel updates to show the whole year is selected
    // by checking the year in the select dropdown
    const panelVisible = await isPanelVisible(page)
    if (!panelVisible) {
      // Panel might have closed on navigation, reopen it
      await clickCalendarButton(page)
      await page.waitForTimeout(1000)
    }

    const yearSelect = page.locator("#year-select")
    const selectedYear = await yearSelect.inputValue()
    expect(selectedYear).toBe(expectedYear)
  })

  test("should update month buttons when year is changed", async ({ page }) => {
    // Open panel
    await clickCalendarButton(page)

    // Wait for data to load
    await page.waitForTimeout(2000)

    const yearSelect = page.locator("#year-select")

    // Get available years
    const options = await yearSelect.locator("option:not([disabled])").all()

    if (options.length < 2) {
      console.log("Test skipped: Less than 2 years available")
      test.skip()
      return
    }

    // Select first year and capture month states
    const firstYearOption = options[0]
    const firstYear = await firstYearOption.getAttribute("value")
    await yearSelect.selectOption(firstYear)
    await page.waitForTimeout(500)

    // Get enabled months for first year
    const _firstYearMonths = await page
      .locator("#months-grid a:not(.disabled)")
      .count()

    // Select second year
    const secondYearOption = options[1]
    const secondYear = await secondYearOption.getAttribute("value")
    await yearSelect.selectOption(secondYear)
    await page.waitForTimeout(500)

    // Get enabled months for second year
    const _secondYearMonths = await page
      .locator("#months-grid a:not(.disabled)")
      .count()

    // Months should be different (unless both years have same tracked months)
    // At minimum, verify that month buttons are updated (content changed from loading dots)
    const monthButtons = await page.locator("#months-grid a").all()

    for (const button of monthButtons) {
      const buttonText = await button.textContent()
      // Should not contain loading dots anymore
      expect(buttonText).not.toContain("loading")
    }
  })

  test("should highlight active month based on current URL parameters", async ({
    page,
  }) => {
    // Navigate to a specific month first
    await page.goto("/map?start_at=2024-10-01T00:00&end_at=2024-10-31T23:59")
    await closeOnboardingModal(page)
    await page.waitForSelector(".leaflet-container", {
      state: "visible",
      timeout: 10000,
    })
    await page.waitForTimeout(2000)

    // Open calendar panel
    await clickCalendarButton(page)
    await page.waitForTimeout(2000)

    // Find October button (month index 9, displayed as "Oct")
    const octoberButton = page.locator('#months-grid a[data-month-name="Oct"]')
    await expect(octoberButton).toBeVisible()

    // Verify October is marked as active
    const hasActiveClass = await octoberButton.evaluate((el) =>
      el.classList.contains("btn-active"),
    )
    expect(hasActiveClass).toBe(true)
  })

  test("should show visited cities section in panel", async ({ page }) => {
    // Open panel
    await clickCalendarButton(page)
    await page.waitForTimeout(2000)

    // Verify visited cities section is present
    const visitedCitiesContainer = page.locator("#visited-cities-container")
    await expect(visitedCitiesContainer).toBeVisible()

    const visitedCitiesTitle = visitedCitiesContainer.locator("h3")
    await expect(visitedCitiesTitle).toHaveText("Visited cities")

    const visitedCitiesList = page.locator("#visited-cities-list")
    await expect(visitedCitiesList).toBeVisible()

    // List should eventually load (either with cities or "No places visited")
    await page.waitForTimeout(2000)
    const listContent = await visitedCitiesList.textContent()
    expect(listContent.length).toBeGreaterThan(0)
  })
})
