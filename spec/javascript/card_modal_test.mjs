import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/card_modal_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace(/^import .*\n/gm, "")
const moduleUrl = `data:text/javascript;base64,${Buffer.from(`class Controller {}\n${source}\n//# sourceURL=card_modal_controller.js`).toString("base64")}`
const { default: CardModalController } = await import(moduleUrl)
globalThis.window = { location: { origin: "http://localhost:3016" } }

function fixture() {
  const document = { activeElement: null, scrollY: 640 }

  function node(name) {
    return {
      name,
      parentNode: null,
      children: [],
      dataset: {},
      focusCalls: [],
      style: {
        removed: [],
        removeProperty(property) {
          this.removed.push(property)
        },
      },
      get isConnected() {
        return this === document.body || !!this.parentNode?.isConnected
      },
      get nextSibling() {
        const siblings = this.parentNode?.children || []
        return siblings[siblings.indexOf(this) + 1] || null
      },
      contains(other) {
        return (
          this === other || this.children.some((child) => child.contains(other))
        )
      },
      remove() {
        if (this.contains(document.activeElement)) {
          document.activeElement = document.body
        }
        if (this.parentNode) {
          const siblings = this.parentNode.children
          siblings.splice(siblings.indexOf(this), 1)
        }
        this.parentNode = null
      },
      insertBefore(child, next) {
        if (next && next.parentNode !== this) {
          throw new Error("NotFoundError: reference node is no longer a child")
        }
        child.remove()
        const index = next ? this.children.indexOf(next) : this.children.length
        this.children.splice(index, 0, child)
        child.parentNode = this
      },
      replaceChildren(...children) {
        for (const child of [...this.children]) child.remove()
        for (const child of children) this.insertBefore(child, null)
      },
      querySelector(selector) {
        return selector === ".ach-card" ? this.card : null
      },
      removeAttribute(attribute) {
        if (attribute === "data-achievement-card-locked-value") {
          delete this.dataset.achievementCardLockedValue
        }
      },
      focus(options) {
        this.focusCalls.push(options)
        if (!this.isConnected) return
        document.activeElement = this
        if (!options?.preventScroll) document.scrollY = 0
      },
    }
  }

  document.body = node("body")
  const grid = node("grid")
  const wrap = node("trigger")
  const card = node("card")
  const next = node("next card")
  const dialog = node("dialog")
  const stage = node("stage")
  const closeButton = node("close button")
  wrap.card = card
  wrap.dataset.achievementCardLockedValue = "true"
  document.body.replaceChildren(grid, dialog)
  grid.replaceChildren(wrap, next)
  wrap.replaceChildren(card)
  dialog.replaceChildren(closeButton, stage)

  const controller = new CardModalController()
  controller.labelsValue = {
    public_link: "Public link",
    embed_code: "Embed code",
    iframe_title: "Dawarich achievement",
    copy: "Copy",
    copied: "Copied",
    share_error: "Couldn't update sharing. Please try again.",
    copy_error:
      "Couldn't copy automatically. Select the link or code and copy it manually.",
  }
  controller.dialogTarget = dialog
  controller.stageTarget = stage
  controller.toolsTarget = { hidden: false }
  controller.panelTarget = { hidden: false }
  controller.hasErrorTarget = false
  dialog.open = false
  dialog.showModal = () => {
    dialog.open = true
    closeButton.focus({ preventScroll: true })
  }
  dialog.close = () => {
    dialog.open = false
    // Moving the focused trigger before showModal loses the native return
    // target. The close event must explicitly restore focus after reinsertion.
    document.activeElement = document.body
    controller.restore()
  }
  document.activeElement = wrap

  function open(key = "Enter") {
    let prevented = false
    const lockedValue = wrap.dataset.achievementCardLockedValue
    controller.openOnKey({
      key,
      currentTarget: wrap,
      preventDefault() {
        prevented = true
      },
    })
    assert.equal(prevented, true)
    assert.equal(dialog.open, true)
    assert.equal(wrap.parentNode, stage)
    assert.equal(wrap.children[0], card, "the existing card/map node is moved")
    assert.equal(wrap.dataset.achievementCardLockedValue, lockedValue)
  }

  return { controller, document, dialog, grid, wrap, next, stage, open }
}

function sharingFixture() {
  const context = fixture()
  const { controller, wrap, grid } = context
  wrap.dataset.shareKey = "continent_europe"
  wrap.dataset.shareToggle = "/achievements/continent_europe/toggle_sharing"
  wrap.dataset.shareShared = "false"
  controller.hasFeaturedTarget = true
  controller.featuredTarget = grid
  grid.querySelector = () => (grid.contains(wrap) ? wrap : null)
  controller.hasCreateFormTarget = true
  controller.createFormTarget = { hidden: false }
  controller.hasDisableFormTarget = true
  controller.disableFormTarget = { hidden: true }
  controller.hasPublicLinkTarget = true
  controller.publicLinkTarget = { hidden: true }
  controller.sharingButtonTargets = [{ disabled: false }, { disabled: false }]
  controller.hasErrorTarget = true
  controller.errorTarget = { hidden: true }
  controller.panelLabelTarget = {}
  controller.outputTarget = {
    value: "",
    focus(options) {
      this.focusOptions = options
    },
    select() {
      this.selected = true
    },
  }
  controller.hasCopyBtnTarget = true
  controller.copyBtnTarget = { textContent: "Copy" }
  controller.unshareBtnTarget = { hidden: true }
  return context
}

test("Create public link opens the preview and reveals the URL without navigation", async () => {
  const { controller, dialog, wrap } = sharingFixture()
  const requests = []
  controller.postToggle = async (enabled, url) => {
    requests.push({ enabled, url })
    return { enabled, url: "/shared/achievements/demo" }
  }
  let prevented = false
  await controller.createPublicLink({
    preventDefault() {
      prevented = true
    },
  })
  assert.equal(prevented, true)
  assert.equal(dialog.open, true)
  assert.deepEqual(requests, [{ enabled: true, url: wrap.dataset.shareToggle }])
  assert.equal(controller.panelTarget.hidden, false)
  assert.equal(
    controller.outputTarget.value,
    "http://localhost:3016/shared/achievements/demo",
  )
  assert.deepEqual(controller.outputTarget.focusOptions, {
    preventScroll: true,
  })
  assert.equal(controller.createFormTarget.hidden, true)
  assert.equal(controller.disableFormTarget.hidden, false)
  assert.equal(controller.publicLinkTarget.href, controller.outputTarget.value)
  await controller.share()
  assert.equal(requests.length, 1, "an existing URL is reused, not toggled off")
})

test("sharing disables duplicate requests and re-enables controls after failure", async () => {
  const { controller, open } = sharingFixture()
  open()
  let resolve
  let calls = 0
  controller.postToggle = () => {
    calls += 1
    return new Promise((done) => {
      resolve = done
    })
  }
  const pending = controller.share()
  assert.equal(
    controller.sharingButtonTargets.every((button) => button.disabled),
    true,
  )
  await controller.share()
  assert.equal(calls, 1)
  resolve(null)
  await pending
  assert.equal(controller.panelTarget.hidden, true)
  assert.equal(controller.errorTarget.hidden, false)
  assert.equal(
    controller.sharingButtonTargets.some((button) => button.disabled),
    false,
  )
})

test("a late response updates its original card without opening a stale panel", async () => {
  const { controller, open, wrap } = sharingFixture()
  open()
  let resolve
  controller.postToggle = () =>
    new Promise((done) => {
      resolve = done
    })
  const pending = controller.share()
  controller.close()
  controller.session = {}
  controller.moved = {
    dataset: { shareKey: "country_de", shareShared: "false" },
  }
  controller.shared = false
  resolve({ enabled: true, url: "/shared/achievements/demo" })
  await pending
  assert.equal(wrap.dataset.shareShared, "true")
  assert.equal(controller.moved.dataset.shareShared, "false")
  assert.equal(controller.shared, false)
  assert.equal(controller.panelTarget.hidden, true)
  assert.equal(controller.publicLinkTarget.hidden, false)
})

test("Stop sharing clears the saved URL and synchronizes the header", async () => {
  const { controller, open, wrap } = sharingFixture()
  open()
  controller.postToggle = async (enabled) => ({
    enabled,
    url: enabled ? "/shared/achievements/demo" : null,
  })
  await controller.share()
  await controller.unshare()
  assert.equal(wrap.dataset.shareShared, "false")
  assert.equal(wrap.dataset.shareUrl, undefined)
  assert.equal(controller.panelTarget.hidden, true)
  assert.equal(controller.createFormTarget.hidden, false)
  assert.equal(controller.disableFormTarget.hidden, true)
  assert.equal(controller.publicLinkTarget.hidden, true)
})

test("Embed uses the card-only public view that fits the iframe", async () => {
  const { controller, open } = sharingFixture()
  open()
  controller.postToggle = async () => ({
    enabled: true,
    url: "/shared/achievements/demo",
  })

  await controller.embed()

  assert.match(
    controller.outputTarget.value,
    /src="http:\/\/localhost:3016\/shared\/achievements\/demo\?embed=1"/,
  )
  assert.match(controller.outputTarget.value, /width="360" height="520"/)
})

test("a successful enable response without a URL is treated as an error", async () => {
  const { controller, open, wrap } = sharingFixture()
  open()
  controller.postToggle = async () => ({ enabled: true, url: null })
  await controller.share()
  assert.equal(wrap.dataset.shareShared, "false")
  assert.equal(controller.panelTarget.hidden, true)
  assert.equal(controller.errorTarget.hidden, false)
})

test("Copy reports success only after the clipboard write and offers manual recovery", async () => {
  const { controller, open } = sharingFixture()
  open()
  const original = Object.getOwnPropertyDescriptor(globalThis, "navigator")
  let resolve
  const clipboard = {
    writeText: () =>
      new Promise((done) => {
        resolve = done
      }),
  }
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: { clipboard },
  })
  try {
    const pending = controller.copy()
    assert.equal(controller.copyBtnTarget.textContent, "Copy")
    resolve()
    await pending
    assert.equal(controller.copyBtnTarget.textContent, "Copied")
    controller.showPanel(
      "Public link",
      "http://localhost:3016/shared/achievements/demo",
    )
    clipboard.writeText = async () => {
      throw new Error("Permission denied")
    }
    await controller.copy()
    assert.equal(controller.copyBtnTarget.textContent, "Copy")
    assert.equal(controller.errorTarget.hidden, false)
    assert.equal(controller.outputTarget.selected, true)
  } finally {
    controller.disconnect()
    if (original) Object.defineProperty(globalThis, "navigator", original)
    else delete globalThis.navigator
  }
})

for (const method of ["close button", "Escape", "backdrop"]) {
  test(`${method} restores the same keyboard trigger without scrolling`, () => {
    const context = fixture()
    const { controller, document, dialog, grid, wrap, next, stage } = context
    context.open()

    if (method === "close button") controller.close()
    if (method === "Escape") dialog.close()
    if (method === "backdrop") controller.backdrop({ target: dialog })

    assert.equal(dialog.open, false)
    assert.deepEqual(grid.children, [wrap, next])
    assert.deepEqual(stage.children, [])
    assert.equal(document.activeElement.name, "trigger")
    assert.ok(document.activeElement === wrap)
    assert.deepEqual(wrap.focusCalls, [{ preventScroll: true }])
    assert.equal(document.scrollY, 640)
    assert.equal(wrap.dataset.achievementCardLockedValue, "true")
    assert.deepEqual(wrap.style.removed, [
      "--rx",
      "--ry",
      "--mx",
      "--my",
      "--fo",
      "--sc",
      "--gl",
    ])
    assert.equal(controller.moved, null)
    assert.equal(controller.origin, null)

    controller.restore()
    assert.equal(
      wrap.focusCalls.length,
      1,
      "a repeated close event is harmless",
    )
  })
}

test("Space opens the modal and clicking its contents does not close it", () => {
  const { controller, dialog, wrap, open } = fixture()
  open(" ")

  controller.backdrop({ target: wrap })

  assert.equal(dialog.open, true)
})

test("Turbo cache preparation restores the live card before the DOM is snapshotted", () => {
  const { controller, dialog, grid, wrap, next, stage, open } = fixture()
  open()

  controller.prepareForCache()

  assert.equal(dialog.open, false)
  assert.deepEqual(grid.children, [wrap, next])
  assert.deepEqual(stage.children, [])
  assert.equal(controller.moved, null)
  assert.equal(controller.origin, null)
})

test("restoration appends safely if the original next sibling was removed", () => {
  const { controller, document, grid, wrap, next, open } = fixture()
  open()
  next.remove()

  assert.doesNotThrow(() => controller.close())

  assert.deepEqual(grid.children, [wrap])
  assert.equal(document.activeElement, wrap)
})

test("restoration does not steal focus when the original grid was disconnected", () => {
  const { controller, document, grid, wrap, stage, open } = fixture()
  open()
  grid.remove()

  assert.doesNotThrow(() => controller.close())

  assert.equal(wrap.parentNode, grid)
  assert.deepEqual(stage.children, [])
  assert.equal(document.activeElement, document.body)
  assert.deepEqual(wrap.focusCalls, [])
  assert.equal(controller.moved, null)
  assert.equal(controller.origin, null)
})

test("restoration leaves no stale modal card if the trigger had no parent", () => {
  const { controller, document, wrap, stage, open } = fixture()
  wrap.remove()
  open()

  assert.doesNotThrow(() => controller.close())

  assert.equal(wrap.parentNode, null)
  assert.deepEqual(stage.children, [])
  assert.equal(document.activeElement, document.body)
  assert.deepEqual(wrap.focusCalls, [])
  assert.equal(controller.moved, null)
  assert.equal(controller.origin, null)
})

test("opening an unlocked card does not create a locked value", () => {
  const { controller, wrap, open } = fixture()
  delete wrap.dataset.achievementCardLockedValue
  open()

  assert.equal(wrap.dataset.achievementCardLockedValue, undefined)

  controller.close()

  assert.equal(wrap.dataset.achievementCardLockedValue, undefined)
})
