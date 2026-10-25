import { expect, test as setup } from "@playwright/test"

setup(
  "sign in as the user who has not answered the changelog prompt",
  async ({ page }) => {
    await page.goto("/users/sign_in")
    const token = await page
      .locator('form input[name="authenticity_token"]')
      .first()
      .inputValue()
    const response = await page.request.post("/users/sign_in", {
      form: {
        authenticity_token: token,
        "user[email]": "changelog-prompt@dawarich.app",
        "user[password]": "safepassword",
      },
      maxRedirects: 0,
    })
    expect(response.status()).toBe(303)
    await page
      .context()
      .storageState({ path: "e2e/temp/.auth/changelog-prompt-user.json" })
  },
)
