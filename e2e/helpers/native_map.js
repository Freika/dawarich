import { expect } from "@playwright/test"

export async function closeOnboardingModal(page) {
  await expect(page.locator(".phx-connected #getting_started")).toBeAttached()
  const dialog = page.locator("#getting_started")
  if ((await dialog.count()) && (await dialog.evaluate(node => node.open))) {
    await dialog.locator('button[form="native-onboarding-dismiss"]:visible').click()
    await expect(dialog).not.toHaveAttribute("open")
  }
}

export async function waitForMapLibre(page) {
  await expect(page.locator("#native-map")).toHaveAttribute("data-map-state", "ready")
  await expect(page.locator("#native-map canvas")).toBeVisible()
}
