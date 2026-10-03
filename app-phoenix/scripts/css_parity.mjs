import { readFileSync, writeFileSync } from "node:fs"

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
const DIGEST = /-[0-9a-f]{64}(?=\.)/

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
  const { chromium } = await import("@playwright/test")
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

function compare(args) {
  const strict = args.includes("--strict")
  const [left, right] = args.filter((arg) => arg !== "--strict")
  const a = JSON.parse(readFileSync(left, "utf8"))
  const b = JSON.parse(readFileSync(right, "utf8"))
  let differences = 0
  const report = (line) => {
    differences++
    console.log(line)
  }
  const logical = (sheets) =>
    new Map(
      sheets.map(([href, hash]) => [href.replace(DIGEST, ""), [href, hash]]),
    )
  for (const path of PAGES) {
    const sheets = logical(a[path].sheets)
    const others = logical(b[path].sheets)
    let sharedSheets = 0
    for (const [name, [href, hash]] of others) {
      const mine = sheets.get(name)
      if (!mine) {
        console.log(`${path} ${name}: right only`)
        if (strict) differences++
        continue
      }
      sharedSheets++
      if (mine[1] !== hash)
        report(`${path} ${name}: body differs (${mine[0]} -> ${href})`)
    }
    for (const name of sheets.keys()) {
      if (others.has(name)) continue
      console.log(`${path} ${name}: left only`)
      if (strict) differences++
    }
    if (sharedSheets === 0) report(`${path}: no stylesheet in common`)
    let shared = 0
    for (const [key, value] of Object.entries(a[path].styles)) {
      if (!(key in b[path].styles)) continue
      shared++
      if (b[path].styles[key] !== value)
        report(`${path} ${key}: ${value} -> ${b[path].styles[key]}`)
    }
    const leftOnly = Object.keys(a[path].styles).length - shared
    const rightOnly = Object.keys(b[path].styles).length - shared
    console.log(
      `${path}: ${shared} shared, ${leftOnly} left only, ${rightOnly} right only`,
    )
    if (shared === 0) report(`${path}: no element in common`)
    if (strict && leftOnly + rightOnly > 0)
      report(`${path}: elements on one side only`)
  }
  process.exit(differences === 0 ? 0 : 1)
}

const [command, ...args] = process.argv.slice(2)
await (command === "compare" ? compare(args) : capture([command, ...args]))
