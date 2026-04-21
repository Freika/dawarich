import { open as openFile, stat as statFile, unlink } from "node:fs/promises"
import { join } from "node:path"
import { fileURLToPath } from "node:url"
import { expect, test } from "@playwright/test"

const __dirname = fileURLToPath(new URL(".", import.meta.url))

const FIXTURE_GPX = join(
  __dirname,
  "../spec/fixtures/files/gpx/gpx_track_single_segment.gpx",
)

test.describe("zip at rest", () => {
  test("uploaded GPX is stored as a zip and imports correctly", async ({
    page,
  }) => {
    await page.goto("/imports/new")

    // The upload controller handles ActiveStorage direct uploads.
    // Set the file on the hidden file input used by the upload controller.
    const fileInput = page
      .locator('[data-controller="upload"] input[type="file"]')
      .first()
    await fileInput.setInputFiles(FIXTURE_GPX)

    // Wait for the upload_controller to finish uploading to ActiveStorage
    // and show the success flash / enable the submit button.
    await expect(page.getByText(/uploaded successfully/i)).toBeVisible({
      timeout: 30_000,
    })

    // Submit the import form
    const submitBtn = page.locator(
      'input[type="submit"], button[type="submit"]',
    )
    await submitBtn.first().click()

    // Should redirect to the imports list
    await expect(page).toHaveURL(/\/imports/, { timeout: 15_000 })

    // Wait for Sidekiq to process the import (status reaches "completed")
    await expect(page.getByText(/completed/i).first()).toBeVisible({
      timeout: 60_000,
    })

    // If there is a download link for the raw import blob, verify its
    // content-type header is application/zip (zip-at-rest).
    const downloadLink = page
      .locator("a")
      .filter({ hasText: /download/i })
      .first()

    await expect(downloadLink).toBeVisible()

    const href = await downloadLink.getAttribute("href")
    const response = await page.request.get(href)
    expect(response.headers()["content-type"]).toContain("application/zip")
  })

  test("exported GPX is delivered as a .zip file", async ({ page }) => {
    await page.goto("/exports")

    // Fill in date range – use a range that has demo data
    const startLabel = page.getByLabel(/start/i).first()
    const endLabel = page.getByLabel(/end/i).first()

    if ((await startLabel.count()) > 0) {
      await startLabel.fill("2021-01-01")
    }
    if ((await endLabel.count()) > 0) {
      await endLabel.fill("2021-01-02")
    }

    // Select GPX format if a radio/select is present
    const formatRadio = page.getByLabel(/gpx/i)
    if ((await formatRadio.count()) > 0) {
      await formatRadio.first().check()
    }

    // Submit the export form
    const exportBtn = page
      .locator('input[type="submit"], button[type="submit"]')
      .filter({ hasText: /export/i })
      .first()
    await exportBtn.click()

    // A flash confirming the export was initiated
    await expect(
      page
        .getByText(/successfully initiated/i)
        .or(page.getByText(/export.*created/i))
        .or(page.getByText(/export.*queued/i)),
    ).toBeVisible({ timeout: 15_000 })

    // Wait for Sidekiq to complete the export
    await expect(page.getByText(/completed/i).first()).toBeVisible({
      timeout: 60_000,
    })

    // Download the export and verify it is a real ZIP (PK magic bytes)
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      page
        .getByRole("link", { name: /download/i })
        .first()
        .click(),
    ])

    const suggested = download.suggestedFilename()
    expect(suggested.endsWith(".zip")).toBe(true)

    const tmp = join("/tmp", `dl_${Date.now()}_${suggested}`)
    await download.saveAs(tmp)

    const info = await statFile(tmp)
    expect(info.size).toBeGreaterThan(0)

    const fd = await openFile(tmp, "r")
    const buf = Buffer.alloc(4)
    await fd.read({ buffer: buf, position: 0, length: 4 })
    await fd.close()

    // ZIP magic bytes: PK (0x50 0x4B)
    expect(buf[0]).toBe(0x50)
    expect(buf[1]).toBe(0x4b)

    await unlink(tmp)
  })
})
