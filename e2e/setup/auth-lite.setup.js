import { test as setup } from "@playwright/test"
import { disableGlobeProjection } from "../v2/helpers/setup.js"

const authFile = "e2e/temp/.auth/lite-user.json"

setup("authenticate lite user", async ({ page }) => {
  await page.goto("/users/sign_in", {
    waitUntil: "domcontentloaded",
    timeout: 30000,
  })

  await page.fill('input[name="user[email]"]', "lite@dawarich.app")
  await page.fill('input[name="user[password]"]', "password")

  await page.click('input[type="submit"][value="Log in"]')

  await page.waitForURL(/\/map(\/v[12])?/, { timeout: 10000 })

  await disableGlobeProjection(page)

  await page.context().storageState({ path: authFile })
})
