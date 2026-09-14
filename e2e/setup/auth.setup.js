import { readFile } from "node:fs/promises"
import { expect, test as setup } from "@playwright/test"

setup("authenticate map editing user", async ({ page }) => {
  const seed = JSON.parse(await readFile("e2e/temp/seed.json", "utf8"))
  await page.goto("/users/sign_in")
  await page.locator("#user_email").fill(seed.edit_email)
  await page.locator("#user_password").fill(seed.password)
  await page.getByRole("button", { name: /log in/i }).click()
  await expect(page).toHaveURL(/\/map(?:\/v2)?(?:\?|$)/)
  await page.context().storageState({ path: "e2e/temp/.auth/user.json" })
})
