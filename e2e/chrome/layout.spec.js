import { expect, test } from "@playwright/test"

for (const locale of ["en", "de"]) {
  for (const width of [1280, 390]) {
    test(`shared chrome menus and theme preserve the page (${locale}, ${width})`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/tags?locale=${locale}`)
      await expect(page.locator("html")).toHaveAttribute("lang", locale)
      const version = page.locator("#version-indicator > .badge")
      if (width === 390) {
        await expect(version).toBeHidden()
        await page.locator('summary[aria-controls="mobile-navigation-menu"]').click()
      } else {
        await expect(version).toBeVisible()
        const notifications = page.locator("details", { has: page.locator("#notifications-list") })
        await notifications.locator(":scope > summary").click()
        await expect(page.locator('#notifications-list a[href="/notifications"]')).toBeVisible()
        await notifications.locator(":scope > summary").click()
      }
      const current = await page.locator("html").getAttribute("data-theme")
      const target = current === "dawarich" ? "dark" : "light"
      await page.locator(`a[href="/settings/theme?theme=${target}"]`).filter({ visible: true }).click()
      await expect(page.locator("html")).toHaveAttribute("data-theme", target === "light" ? "dawarich" : "dawarich-dark")
      await expect(page).toHaveURL(/\/tags(?:\?|$)/)
      if (width === 390)
        await page.locator('summary[aria-controls="mobile-navigation-menu"]').click()
      const restore = current === "dawarich" ? "light" : "dark"
      await page.locator(`a[href="/settings/theme?theme=${restore}"]`).filter({ visible: true }).click()
      await expect(page.locator("html")).toHaveAttribute("data-theme", current)
      expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)).toBe(false)
    })
  }
}

test.describe("guest chrome", () => {
  test.use({ storageState: { cookies: [], origins: [] } })

  test("sign-in hides private navigation and the auth flash dismisses locally", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 })
    await page.goto("/notifications?locale=en")
    await expect(page).toHaveURL(/\/users\/sign_in(?:\?|$)/)
    await expect(page.locator("#mobile-navigation-menu")).toHaveCount(0)
    await expect(page.locator(".navbar-center")).toHaveCount(0)
    await expect(page.locator('.navbar a[href="/users/sign_in"]')).toHaveCount(0)
    const flash = page.locator("#flash-messages [role=alert]").first()
    await expect(flash).toBeVisible()
    await expect(flash.locator("svg")).toHaveCount(2)
    await flash.getByRole("button", { name: "Close", exact: true }).click()
    await expect(flash).toBeHidden()
    await page.goto("/users/password/new?locale=en")
    await expect(page.locator('.navbar a[href="/users/sign_in"]')).toHaveCount(1)
    expect(await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth)).toBe(false)
  })
})
