import { readFileSync } from "node:fs"
import { expect, test } from "./evidence.js"
import {
  createClientZipImport,
  createPlainImport,
  fixture,
  nativePage,
  registerAndSignIn,
  row,
  settings,
} from "./helpers.js"
import {
  deletionEvidence,
  downloadCommandEvidence,
  importEvidence,
  storedBlobEvidence,
} from "./proof.js"

for (const scenario of [
  {
    kind: "plain-producer",
    locale: "en",
    zone: "Europe/Berlin",
    completed: "Completed",
    upload: createPlainImport,
  },
  {
    kind: "client-zip-ui",
    locale: "de",
    zone: "America/New_York",
    completed: "Abgeschlossen",
    upload: createClientZipImport,
  },
]) {
  test(`${scenario.kind}: native completion, owner edit/download/deletion and ${scenario.locale}/${scenario.zone}`, async ({
    page,
    browser,
    evidence,
  }, testInfo) => {
    const owner = await registerAndSignIn(page, scenario.kind)
    await settings(page, scenario.locale, scenario.zone)
    evidence.phase("native-upload")
    const input = fixture(scenario.kind)
    await scenario.upload(page, input, evidence)
    let imported = row(page, input.name)
    await expect(imported).toBeVisible()
    const id = await imported.getAttribute("data-import-id")
    expect(id).toMatch(/^[1-9]\d*$/)

    let subsequentNavigations = 0
    page.on("framenavigated", (frame) => {
      if (frame === page.mainFrame()) subsequentNavigations++
    })
    await expect(imported.locator("[data-status-display]")).toContainText(
      scenario.completed,
      { timeout: 120000 },
    )
    await expect(imported.locator("[data-points-count]")).toHaveText("3")
    expect(subsequentNavigations).toBe(0)
    await expect(page.locator("html")).toHaveAttribute("lang", scenario.locale)
    await evidence.screenshot(page, "native-completed-index")

    await expect
      .poll(
        () =>
          importEvidence(id)?.commands?.find(
            (command) => command.handler === "imports.process_gpx",
          )?.job_state,
        { timeout: 30000 },
      )
      .toBe("completed")
    const proof = importEvidence(id)
    expect(proof).toMatchObject({
      status: 2,
      source: 4,
      processed: 3,
      actual_points: 3,
      owner_email: owner,
      locale: scenario.locale,
    })
    expect(proof.commands).toHaveLength(1)
    expect(proof.commands[0]).toMatchObject({
      type: "imports.process_gpx",
      version: 1,
      state: "dispatched",
      worker: "Dawarich.Imports.ProcessGpxWorker",
      job_state: "completed",
      handler: "imports.process_gpx",
      payload: { import_id: Number(id), time_zone: scenario.zone },
    })
    const stored = storedBlobEvidence(proof)
    expect(stored.bytes).toBe(proof.blob_bytes)
    expect(stored.checksum).toBe(proof.blob_checksum)
    const metadata =
      typeof proof.blob_metadata === "string"
        ? JSON.parse(proof.blob_metadata)
        : proof.blob_metadata
    if (scenario.kind === "client-zip-ui") {
      expect(proof.blob_filename).toBe(`${input.name}.zip`)
      expect(stored.magic).toBe("504b0304")
      expect(metadata).toMatchObject({
        dawarich_client_wrapped: true,
        dawarich_original_filename: input.name,
      })
    } else {
      expect(proof.blob_filename).toBe(input.name)
      expect(stored.magic).toBe("3c3f786d")
    }
    const { owner_email: _email, blob_key: _key, ...publicProof } = proof
    await testInfo.attach("native-processing-and-storage-proof", {
      body: JSON.stringify({ ...publicProof, stored }, null, 2),
      contentType: "application/json",
    })

    evidence.phase("owner-edit")
    await imported.getByRole("link", { name: input.name, exact: true }).click()
    await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
    await page.locator(`a[href="/imports/${id}/edit"]`).click()
    await expect(page).toHaveURL(new RegExp(`/imports/${id}/edit$`))
    await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
    const editedName = `Rhéin & 東京 — ${input.name}`
    const editForm = page
      .locator(`form[action="/imports/${id}"]`)
      .filter({ has: page.locator('input[name="import[name]"]') })
    await editForm.locator('input[name="import[name]"]').fill(editedName)
    await expect(editForm.locator('select[name="import[source]"]')).toHaveValue(
      "gpx",
    )
    await evidence.screenshot(page, "native-owner-edit-form")
    const updatedResponse = page.waitForResponse(
      (response) =>
        new URL(response.url()).pathname === `/imports/${id}` &&
        response.request().method() === "POST",
    )
    await editForm.getByRole("button").click()
    const updated = await updatedResponse
    expect(updated.status()).toBe(303)
    expect(updated.headers()["x-dawarich-handler"]).toBe("phoenix-imports")
    await expect(page).toHaveURL(/\/imports$/)
    await nativePage(page, "/imports")
    imported = row(page, editedName)
    await expect(imported).toBeVisible()
    await expect(row(page, input.name)).toHaveCount(0)
    await expect(imported).toHaveAttribute("data-import-id", id)
    expect(importEvidence(id)).toMatchObject({
      name: editedName,
      source: 4,
      status: 2,
      actual_points: 3,
    })
    await evidence.screenshot(page, "native-owner-edit-persisted")

    evidence.phase("owner-download")
    const isDownload = (response) =>
      new URL(response.url()).pathname === `/imports/${id}/download`
    const pendingResponse =
      scenario.kind === "client-zip-ui"
        ? page.waitForResponse(
            (response) => isDownload(response) && response.status() === 202,
          )
        : null
    const downloadResponse = page.waitForResponse(
      (response) => isDownload(response) && response.status() === 200,
    )
    const [download] = await Promise.all([
      page.waitForEvent("download"),
      imported.locator(`a[href="/imports/${id}/download"]`).click(),
    ])
    const response = await downloadResponse
    if (pendingResponse) {
      const pending = await pendingResponse
      expect(pending.headers()["x-dawarich-handler"]).toBe("phoenix-imports")
      expect(pending.headers().refresh).toBe("3")
      await expect
        .poll(
          () =>
            downloadCommandEvidence(id)?.some(
              (command) =>
                command.job_state === "completed" &&
                command.handler === "imports.prepare_download",
            ),
          { timeout: 30000 },
        )
        .toBeTruthy()
      await testInfo.attach("native-prepared-download-proof", {
        body: JSON.stringify(downloadCommandEvidence(id)),
        contentType: "application/json",
      })
    }
    expect(response.headers()["x-dawarich-handler"]).toBe("phoenix-imports")
    expect(response.ok()).toBeTruthy()
    expect(download.suggestedFilename()).toBe(editedName)
    expect(await download.failure()).toBeNull()
    expect(readFileSync(await download.path())).toEqual(input.buffer)
    evidence.downloaded(id)
    await nativePage(page, "/imports")
    await expect(imported).toBeVisible()

    evidence.phase("foreign-authorization")
    const foreignContext = await browser.newContext({
      baseURL: process.env.NATIVE_IMPORTS_BASE_URL,
    })
    try {
      const foreignPage = await foreignContext.newPage()
      evidence.watch(foreignPage, "foreign")
      await registerAndSignIn(foreignPage, "foreign")
      await nativePage(foreignPage, "/imports")
      await expect(row(foreignPage, editedName)).toHaveCount(0)
      await evidence.screenshot(foreignPage, "native-foreign-empty-index")
      const csrf = await foreignPage
        .locator('meta[name="csrf-token"]')
        .getAttribute("content")
      for (const suffix of ["", "/edit", "/download"]) {
        const denied = await foreignPage.request.get(
          `/imports/${id}${suffix}`,
          { maxRedirects: 0 },
        )
        evidence.protocol(`foreign GET ${suffix || "/show"}`, denied)
        expect(denied.status()).toBe(303)
        expect(denied.headers()["x-dawarich-handler"]).toBeUndefined()
        expect(await denied.text()).not.toContain(editedName)
      }
      const update = await foreignPage.request.patch(`/imports/${id}`, {
        form: {
          authenticity_token: csrf,
          "import[name]": "forbidden foreign edit",
        },
        maxRedirects: 0,
      })
      evidence.protocol("foreign PATCH", update)
      expect(update.status()).toBe(303)
      expect(update.headers()["x-dawarich-handler"]).toBeUndefined()
      const remove = await foreignPage.request.delete(`/imports/${id}`, {
        headers: { "X-CSRF-Token": csrf },
        maxRedirects: 0,
      })
      evidence.protocol("foreign DELETE", remove)
      expect(remove.status()).toBe(303)
      expect(remove.headers()["x-dawarich-handler"]).toBeUndefined()
      expect(importEvidence(id)).toMatchObject({
        name: editedName,
        status: 2,
        actual_points: 3,
      })
    } finally {
      await foreignContext.close()
    }

    evidence.phase("owner-delete")
    page.once("dialog", (dialog) => dialog.accept())
    await imported.getByTestId("import-delete").click()
    await expect(imported).toHaveCount(0, { timeout: 120000 })
    await expect
      .poll(() => deletionEvidence(id), { timeout: 30000 })
      .toEqual({ imports: 0, points: 0, attachments: 0 })
    await testInfo.attach("native-deletion-proof", {
      body: JSON.stringify(deletionEvidence(id)),
      contentType: "application/json",
    })
    await evidence.screenshot(page, "native-owner-deletion-complete")
  })
}
