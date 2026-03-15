import { expect, test } from "@playwright/test"
import { closeOnboardingModal } from "../helpers/navigation.js"

test.describe("Trips Date Validation", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/trips/new")
    await closeOnboardingModal(page)
  })

  test("validates that start date is earlier than end date on new trip form", async ({
    page,
  }) => {
    // Wait for the form to load
    await page.waitForSelector('input[name="trip[started_at]"]')

    // Fill in trip name
    await page.fill('input[name="trip[name]"]', "Test Trip")

    // Set end date before start date
    await page.fill('input[name="trip[started_at]"]', "2024-12-25T10:00")
    await page.fill('input[name="trip[ended_at]"]', "2024-12-20T10:00")

    // Get the current URL to verify we stay on the same page
    const currentUrl = page.url()

    // Try to submit the form
    const submitButton = page.locator(
      'input[type="submit"], button[type="submit"]',
    )
    await submitButton.click()

    // Wait a bit for potential navigation
    await page.waitForTimeout(500)

    // Verify we're still on the same page (form wasn't submitted)
    expect(page.url()).toBe(currentUrl)

    // Verify the dates are still there (form wasn't cleared)
    const startValue = await page
      .locator('input[name="trip[started_at]"]')
      .inputValue()
    const endValue = await page
      .locator('input[name="trip[ended_at]"]')
      .inputValue()
    expect(startValue).toBe("2024-12-25T10:00")
    expect(endValue).toBe("2024-12-20T10:00")
  })

  test("allows valid date range on new trip form", async ({ page }) => {
    // Wait for the form to load
    await page.waitForSelector('input[name="trip[started_at]"]')

    // Fill in trip name
    await page.fill('input[name="trip[name]"]', "Valid Test Trip")

    // Set valid date range (start before end)
    await page.fill('input[name="trip[started_at]"]', "2024-12-20T10:00")
    await page.fill('input[name="trip[ended_at]"]', "2024-12-25T10:00")

    // Trigger blur to validate
    await page.locator('input[name="trip[ended_at]"]').blur()

    // Give the validation time to run
    await page.waitForTimeout(200)

    // Check that the end date field has no validation error
    const endDateInput = page.locator('input[name="trip[ended_at]"]')
    const validationMessage = await endDateInput.evaluate(
      (el) => el.validationMessage,
    )
    const isValid = await endDateInput.evaluate((el) => el.validity.valid)

    expect(validationMessage).toBe("")
    expect(isValid).toBe(true)
  })

  test("validates dates when updating end date to be earlier than start date", async ({
    page,
  }) => {
    // Wait for the form to load
    await page.waitForSelector('input[name="trip[started_at]"]')

    // Fill in trip name
    await page.fill('input[name="trip[name]"]', "Test Trip")

    // First set a valid range
    await page.fill('input[name="trip[started_at]"]', "2024-12-20T10:00")
    await page.fill('input[name="trip[ended_at]"]', "2024-12-25T10:00")

    // Now change start date to be after end date
    await page.fill('input[name="trip[started_at]"]', "2024-12-26T10:00")

    // Get the current URL to verify we stay on the same page
    const currentUrl = page.url()

    // Try to submit the form
    const submitButton = page.locator(
      'input[type="submit"], button[type="submit"]',
    )
    await submitButton.click()

    // Wait a bit for potential navigation
    await page.waitForTimeout(500)

    // Verify we're still on the same page (form wasn't submitted)
    expect(page.url()).toBe(currentUrl)

    // Verify the dates are still there (form wasn't cleared)
    const startValue = await page
      .locator('input[name="trip[started_at]"]')
      .inputValue()
    const endValue = await page
      .locator('input[name="trip[ended_at]"]')
      .inputValue()
    expect(startValue).toBe("2024-12-26T10:00")
    expect(endValue).toBe("2024-12-25T10:00")
  })
})
