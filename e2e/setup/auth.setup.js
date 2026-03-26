import { test as setup } from "@playwright/test"
import { disableGlobeProjection } from "../v2/helpers/setup.js"

const authFile = "e2e/temp/.auth/user.json"

setup("authenticate", async ({ page }) => {
  // Navigate to login page with more lenient waiting
  await page.goto("/users/sign_in", {
    waitUntil: "domcontentloaded",
    timeout: 30000,
  })

  // Fill in credentials
  await page.fill('input[name="user[email]"]', "demo@dawarich.app")
  await page.fill('input[name="user[password]"]', "password")

  // Click login button
  await page.click('input[type="submit"][value="Log in"]')

  // Wait for successful navigation to map (v1 or v2 depending on user preference)
  await page.waitForURL(/\/map(\/v[12])?/, { timeout: 10000 })

  // Dismiss onboarding modal so it doesn't block E2E tests
  await page.evaluate(() =>
    localStorage.setItem("dawarich_onboarding_shown", "true"),
  )
  // Persist onboarding completion server-side
  const csrfToken = await page
    .locator('meta[name="csrf-token"]')
    .getAttribute("content")
  if (csrfToken) {
    await page.request.patch("/settings/onboarding", {
      headers: { "X-CSRF-Token": csrfToken },
    })
  }

  // Disable globe projection to ensure consistent E2E test behavior
  await disableGlobeProjection(page)

  // Save authentication state (includes localStorage with onboarding dismissal)
  await page.context().storageState({ path: authFile })
})
