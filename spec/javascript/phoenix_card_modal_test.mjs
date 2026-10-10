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
const adapter = (
  await readFile(
    new URL(
      "../../app-phoenix/priv/static/js/native_card_modal.js",
      import.meta.url,
    ),
    "utf8",
  )
).replace('"rails_card_modal"', JSON.stringify(moduleUrl))
const { default: CardModalController } = await import(
  `data:text/javascript;base64,${Buffer.from(adapter).toString("base64")}`
)
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
  controller.hasUnshareBtnTarget = true
  return context
}

for (const action of ["share", "embed", "unshare"]) {
  test(`native preview ${action} opens the owner manager without a write`, async () => {
    const { controller, open, wrap } = sharingFixture()
    const requests = []
    const navigation = []
    globalThis.fetch = async (...args) => {
      requests.push(args)
      throw new Error("retired write")
    }
    window.location.assign = (path) => navigation.push(path)
    wrap.dataset.shareManager = "/achievements/continent_europe/sharing"
    open()
    await controller[action]()
    assert.deepEqual(navigation, [wrap.dataset.shareManager])
    assert.deepEqual(requests, [])
    assert.equal(wrap.dataset.shareShared, "false")
    assert.equal(controller.unshareBtnTarget.href, wrap.dataset.shareManager)
  })
}

test("native preview copies an existing public URL and embed without a write", async () => {
  const { controller, open, wrap } = sharingFixture()
  const requests = []
  globalThis.fetch = async (...args) => {
    requests.push(args)
    throw new Error("retired write")
  }
  wrap.dataset.shareShared = "true"
  wrap.dataset.shareUrl = "/shared/achievements/demo"
  wrap.dataset.shareManager = "/achievements/continent_europe/sharing"
  open()
  await controller.share()
  assert.equal(
    controller.outputTarget.value,
    "http://localhost:3016/shared/achievements/demo",
  )
  await controller.embed()
  assert.match(controller.outputTarget.value, /demo\?embed=1/)
  assert.match(controller.outputTarget.value, /width="360" height="520"/)
  assert.deepEqual(requests, [])
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
