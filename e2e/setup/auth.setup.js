import { expect, test as setup } from "@playwright/test"

setup("sign in as the seeded demo user", async ({ page }) => {
  await page.goto("/users/sign_in")
  await page.getByRole("textbox", { name: "Email" }).fill("demo@dawarich.app")
  await page.getByRole("textbox", { name: "Password" }).fill("safepassword")
  await page.getByRole("button", { name: "Log in" }).click()
  await expect(page).toHaveURL(/\/map\/v2/)
  await page.context().storageState({ path: "e2e/temp/.auth/user.json" })
})
