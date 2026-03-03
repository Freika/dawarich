/**
 * Navigation and UI helper functions for Playwright tests
 */

/**
 * Close the onboarding modal if it's open
 * @param {Page} page - Playwright page object
 */
export async function closeOnboardingModal(page) {
  const onboardingModal = page.locator("#getting_started")
  const isModalOpen = await onboardingModal
    .evaluate((dialog) => dialog.open)
    .catch(() => false)
  if (isModalOpen) {
    await page.locator("#getting_started button.btn-primary").click()
    await page.waitForTimeout(500)
  }
}

/**
 * Navigate to the map page and close onboarding modal
 * @param {Page} page - Playwright page object
 */
export async function navigateToMap(page) {
  await page.goto("/map")
  await closeOnboardingModal(page)
}

/**
 * Navigate to a specific date range on the map
 * @param {Page} page - Playwright page object
 * @param {string} startDate - Start date in format 'YYYY-MM-DDTHH:mm'
 * @param {string} endDate - End date in format 'YYYY-MM-DDTHH:mm'
 */
export async function navigateToDate(page, startDate, endDate) {
  const startInput = page.locator(
    'input[type="datetime-local"][name="start_at"]',
  )
  await startInput.clear()
  await startInput.fill(startDate)

  const endInput = page.locator('input[type="datetime-local"][name="end_at"]')
  await endInput.clear()
  await endInput.fill(endDate)

  await page.click('input[type="submit"][value="Search"]')
  await page.waitForLoadState("networkidle")
  await page.waitForTimeout(1000)
}
