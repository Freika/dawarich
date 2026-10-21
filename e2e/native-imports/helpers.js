import { createHash } from "node:crypto"
import { expect, test } from "@playwright/test"

const pageStates = new WeakMap()

function observePage(page) {
  if (pageStates.has(page)) return pageStates.get(page)
  const state = { documentResponse: null, assets: new Set() }
  const origin = new URL(process.env.NATIVE_IMPORTS_BASE_URL).origin
  page.on("response", (response) => {
    const request = response.request()
    if (
      request.isNavigationRequest() &&
      request.frame() === page.mainFrame() &&
      request.method() === "GET" &&
      response.status() === 200 &&
      response.headers()["content-type"]?.startsWith("text/html")
    )
      state.documentResponse = response
  })
  page.on("request", (request) => {
    const url = new URL(request.url())
    if (url.origin === origin && url.pathname.startsWith("/assets/"))
      state.assets.add(request)
  })
  page.on("requestfinished", (request) => state.assets.delete(request))
  page.on("requestfailed", (request) => state.assets.delete(request))
  pageStates.set(page, state)
  return state
}

async function readyPage(page) {
  await page.waitForLoadState("load")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
  await page.waitForFunction(() => window.liveSocket?.isConnected())
  await expect
    .poll(() => observePage(page).assets.size, {
      timeout: 15000,
      message: "page asset requests complete",
    })
    .toBe(0)
}

export function fixture(kind) {
  const token = `${Date.now()}-${Math.random().toString(16).slice(2, 8)}`
  const start = 1709251200 + (Math.floor(Date.now() / 1000) % 16000000)
  const times = [0, 60, 120].map((offset) =>
    new Date((start + offset) * 1000).toISOString(),
  )
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="native-imports-acceptance" xmlns="http://www.topografix.com/GPX/1/1">
<trk><name>Rhéin native acceptance</name><trkseg>${times
    .map(
      (time, n) =>
        `<trkpt lat="50.000${n}" lon="8.000${n}"><ele>120</ele><time>${time}</time></trkpt>`,
    )
    .join("")}
</trkseg></trk></gpx>`
  return {
    name: `native-${kind}-${token}.gpx`,
    mimeType: "application/gpx+xml",
    buffer: Buffer.from(xml),
    times,
  }
}

export async function registerAndSignIn(page, prefix) {
  observePage(page)
  const email = `e2e-native-${prefix}-${Date.now()}-${Math.random().toString(16).slice(2, 8)}@dawarich.test`
  const password = "native-acceptance-password-12"
  const response = await page.request.post("/api/v1/auth/register", {
    data: { email, password, password_confirmation: password },
  })
  expect(
    response.ok(),
    `actual registration returned ${response.status()}`,
  ).toBeTruthy()
  await page.goto("/users/sign_in")
  await page.getByLabel("Email", { exact: true }).fill(email)
  await page.getByLabel("Password", { exact: true }).fill(password)
  await page.getByRole("button", { name: "Log in", exact: true }).click()
  await expect(page).toHaveURL(/\/map/)
  await readyPage(page)
  return email
}

export async function nativePage(page, path) {
  const state = observePage(page)
  const current = state.documentResponse
  const reuse =
    new URL(page.url()).pathname === path &&
    current &&
    new URL(current.url()).pathname === path
  if (!reuse && (await page.locator("[data-phx-main]").count())) {
    await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
    await readyPage(page)
  }
  const response = reuse ? current : await page.goto(path)
  expect(
    response?.ok(),
    `native ${path} returned ${response?.status()}`,
  ).toBeTruthy()
  await expect(page.locator("[data-phx-main]")).toBeVisible()
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
  if (path.startsWith("/imports")) {
    expect(response.status()).toBe(200)
    expect(response.headers()["x-dawarich-handler"]).toBe("phoenix-imports")
    await expect(page.getByTestId("native-imports-root")).toBeVisible()
  }
  const dialog = page.locator("dialog#getting_started")
  const dialogState = (await dialog.count())
    ? await dialog.evaluate((element) => {
        const style = getComputedStyle(element)
        const bounds = element.getBoundingClientRect()
        return {
          open: element.open,
          openAttribute: element.hasAttribute("open"),
          display: style.display,
          visibility: style.visibility,
          opacity: style.opacity,
          width: bounds.width,
          height: bounds.height,
        }
      })
    : { absent: true }
  await test.info().attach("welcome-dialog-bounded-state", {
    body: JSON.stringify({ path, ...dialogState }),
    contentType: "application/json",
  })
  const consent = page.getByRole("button", { name: "No thanks", exact: true })
  if (await consent.isVisible()) {
    await test.info().attach("changelog-consent-bounded-state", {
      body: JSON.stringify(
        await consent.evaluate((element) => ({
          tag: element.tagName,
          text: element.textContent.trim(),
          disabled: element.disabled,
          display: getComputedStyle(element).display,
          visibility: getComputedStyle(element).visibility,
        })),
      ),
      contentType: "application/json",
    })
    const before = test.info().outputPath("changelog-consent-visible.png")
    await page.screenshot({ path: before, fullPage: true })
    await test.info().attach("changelog-consent-visible", {
      path: before,
      contentType: "image/png",
    })
    await consent.click()
    await expect(consent).toBeHidden()
    const after = test.info().outputPath("changelog-consent-dismissed.png")
    await page.screenshot({ path: after, fullPage: true })
    await test.info().attach("changelog-consent-dismissed", {
      path: after,
      contentType: "image/png",
    })
  }
  const welcome = page.locator("dialog#getting_started[open]").filter({
    has: page.getByRole("heading", {
      name: "Welcome to Dawarich!",
      exact: true,
    }),
  })
  if (await welcome.isVisible())
    await welcome
      .getByRole("button", { name: "Skip for now", exact: true })
      .click()
  await readyPage(page)
  return response
}

export async function settings(page, locale, zone) {
  await nativePage(page, "/settings/general")
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
  await page.locator("#timezone").selectOption(zone)
  await page.locator(`label:has(#locale_${locale})`).click()
  const changesLocale =
    (await page.locator("html").getAttribute("lang")) !== locale
  const navigation = changesLocale
    ? page.waitForNavigation({ waitUntil: "load" })
    : null
  await page.locator('#native-general-settings input[type="submit"]').click()
  if (navigation) await navigation
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
  await readyPage(page)
  await expect(
    page.locator("#flash-messages [role=alert]").first(),
  ).toBeVisible()
  await nativePage(page, "/imports")
  await expect(page.locator("html")).toHaveAttribute("lang", locale)
}

export function row(page, name) {
  return page
    .locator("#imports tbody tr")
    .filter({ has: page.getByRole("link", { name, exact: true }) })
}

async function uploadForm(page) {
  await nativePage(page, "/imports/new")
  await page.waitForFunction(() => {
    const form = document.querySelector("#phx-import-upload")
    const main = form?.closest("[data-phx-main]")
    return !!(main && window.liveSocket?.getRootById(main.id)?.getHook(form))
  })
  return page.locator("#phx-import-upload")
}

async function finishUpload(page, form, input, evidence) {
  const progress = form.getByRole("progressbar")
  await expect(progress).toBeVisible()
  await expect(progress).toHaveAttribute("value", "100", { timeout: 30000 })
  await expect(
    form.locator("[data-entry-ref]").getByText("100%", { exact: true }),
  ).toBeVisible()
  await expect(form.getByText(input.name, { exact: true })).toBeVisible()
  const submit = form.getByTestId("import-submit")
  await expect(submit).toBeEnabled()
  if (evidence) await evidence.screenshot(page, "native-upload-100-percent")
  await submit.click()
  await expect(page).toHaveURL(/\/imports$/)
  await expect(page.locator("[data-phx-main].phx-connected")).toBeVisible()
}

export async function createPlainImport(page, input, evidence) {
  const form = await uploadForm(page)
  await page.evaluate(
    ({ name, mimeType, bytes, checksum }) => {
      const form = document.querySelector("#phx-import-upload")
      const main = form.closest("[data-phx-main]")
      const hook = window.liveSocket.getRootById(main.id).getHook(form)
      const file = new File(
        [Uint8Array.from(atob(bytes), (c) => c.charCodeAt(0))],
        name,
        { type: mimeType },
      )
      file.meta = () => ({
        checksum,
        original_filename: name,
        original_size: file.size,
        client_wrapped: false,
      })
      hook.upload("files", [file])
    },
    {
      name: input.name,
      mimeType: input.mimeType,
      bytes: input.buffer.toString("base64"),
      checksum: createHash("md5").update(input.buffer).digest("base64"),
    },
  )
  await finishUpload(page, form, input, evidence)
}

export async function createClientZipImport(page, input, evidence) {
  const form = await uploadForm(page)
  const file = form.getByTestId("import-file-input")
  await expect(file).toBeVisible()
  await file.setInputFiles({
    name: input.name,
    mimeType: input.mimeType,
    buffer: input.buffer,
  })
  await finishUpload(page, form, input, evidence)
}
