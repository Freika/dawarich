import { readFileSync, writeFileSync } from "node:fs"
import { chromium } from "@playwright/test"

const PROPS = [
  "display",
  "position",
  "float",
  "box-sizing",
  "width",
  "height",
  "margin-top",
  "margin-right",
  "margin-bottom",
  "margin-left",
  "padding-top",
  "padding-right",
  "padding-bottom",
  "padding-left",
  "border-top-width",
  "border-right-width",
  "border-bottom-width",
  "border-left-width",
  "border-top-color",
  "border-top-style",
  "border-radius",
  "color",
  "background-color",
  "background-image",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "line-height",
  "letter-spacing",
  "text-align",
  "text-decoration-line",
  "text-transform",
  "white-space",
  "opacity",
  "visibility",
  "overflow-x",
  "overflow-y",
  "box-shadow",
  "outline-style",
  "flex-direction",
  "flex-wrap",
  "justify-content",
  "align-items",
  "gap",
  "grid-template-columns",
  "z-index",
  "transform",
]
const PAGES = ["/stats", "/notifications", "/settings/general"]

async function snapshot(props) {
  const sheets = []
  for (const link of document.querySelectorAll('link[rel="stylesheet"]')) {
    const body = await (await fetch(link.href)).arrayBuffer()
    const hash = await crypto.subtle.digest("SHA-256", body)
    sheets.push([
      new URL(link.href).pathname,
      Array.from(new Uint8Array(hash), (b) =>
        b.toString(16).padStart(2, "0"),
      ).join(""),
    ])
  }
  const counts = {}
  const styles = {}
  for (const element of document.body.querySelectorAll("*")) {
    const signature = `${element.tagName.toLowerCase()}#${element.id}.${[...element.classList].sort().join(".")}`
    counts[signature] = (counts[signature] || 0) + 1
    const style = getComputedStyle(element)
    styles[`${signature}@${counts[signature]}`] = props
      .map((p) => style.getPropertyValue(p))
      .join("|")
  }
  return { sheets, styles }
}

async function capture([base, email, password, out]) {
  const browser = await chromium.launch()
  const page = await browser.newPage({
    viewport: { width: 1440, height: 900 },
    reducedMotion: "reduce",
  })
  await page.goto(`${base}/users/sign_in`)
  await page.fill("#user_email", email)
  await page.fill("#user_password", password)
  await page.press("#user_password", "Enter")
  await page.waitForURL((url) => !url.pathname.startsWith("/users/sign_in"))
  const result = {}
  for (const path of PAGES) {
    await page.goto(`${base}${path}`, { waitUntil: "networkidle" })
    result[path] = await page.evaluate(snapshot, PROPS)
  }
  await browser.close()
  writeFileSync(out, JSON.stringify(result, null, 1))
}

function compare([left, right]) {
  const a = JSON.parse(readFileSync(left, "utf8"))
  const b = JSON.parse(readFileSync(right, "utf8"))
  let differences = 0
  for (const path of PAGES) {
    const sheets = new Map(a[path].sheets)
    for (const [href, hash] of b[path].sheets) {
      if (sheets.has(href) && sheets.get(href) !== hash) {
        differences++
        console.log(`${path} ${href}: body differs`)
      }
    }
    let shared = 0
    for (const [key, value] of Object.entries(a[path].styles)) {
      if (!(key in b[path].styles)) continue
      shared++
      if (b[path].styles[key] !== value) {
        differences++
        console.log(`${path} ${key}: ${value} -> ${b[path].styles[key]}`)
      }
    }
    console.log(
      `${path}: ${shared} shared, ${Object.keys(a[path].styles).length - shared} left only, ${Object.keys(b[path].styles).length - shared} right only`,
    )
  }
  process.exit(differences === 0 ? 0 : 1)
}

const [command, ...args] = process.argv.slice(2)
await (command === "compare" ? compare(args) : capture(args))
