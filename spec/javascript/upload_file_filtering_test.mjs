import assert from "node:assert/strict"
import { File } from "node:buffer"
import { readFile } from "node:fs/promises"
import test from "node:test"

globalThis.File ??= File

function moduleUrl(source) {
  return `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`
}

const fflateUrl = moduleUrl(
  await readFile(
    new URL("../../vendor/javascript/fflate.js", import.meta.url),
    "utf8",
  ),
)
const { unzipSync } = await import(fflateUrl)
const zipUrl = moduleUrl(
  (
    await readFile(
      new URL("../../app/javascript/services/zip_file.js", import.meta.url),
      "utf8",
    )
  ).replace(
    'import { zip } from "fflate"',
    `import { zipSync } from "${fflateUrl}"
    const zip = (files, options, done) => done(null, zipSync(files, options))`,
  ),
)
const { shouldZip } = await import(zipUrl)
const source = (
  await readFile(
    new URL(
      "../../app/javascript/controllers/upload_controller.js",
      import.meta.url,
    ),
    "utf8",
  )
)
  .replace(
    'import { Controller } from "@hotwired/stimulus"',
    "class Controller {}",
  )
  .replace('import { DirectUpload } from "@rails/activestorage"', "")
  .replace(
    'import { translate } from "i18n"',
    "const translate = (key, options) => ({ key, ...options })",
  )
  .replace('from "services/zip_file"', `from "${zipUrl}"`)
  .replace(
    'import Flash from "./flash_controller"',
    "const Flash = { show: (...args) => globalThis.uploadFlashes.push(args) }",
  )
const { default: UploadController } = await import(moduleUrl(source))
const extensions = [
  "json",
  "geojson",
  "gpx",
  "kml",
  "kmz",
  "tcx",
  "fit",
  "csv",
  "rec",
  "zip",
]

function fixture() {
  globalThis.uploadFlashes = []
  const controller = new UploadController()
  controller.inputTarget = { value: "selected" }
  controller.validateZipValue = false
  controller.userTrialValue = false
  return controller
}

test("supported filenames accept empty and generic MIME types", () => {
  const controller = fixture()
  for (const type of [
    "",
    "application/octet-stream",
    "text/xml",
    "application/xml",
  ]) {
    for (const extension of extensions) {
      const file = new File(["track"], `track.${extension}`, { type })
      assert.equal(
        controller.validateFiles([file]),
        true,
        `${file.name}: ${type}`,
      )
    }
  }
  assert.deepEqual(globalThis.uploadFlashes, [])
})

test("supported filename extensions are case insensitive", () => {
  const controller = fixture()
  for (const extension of extensions) {
    const file = new File(["track"], `TRACK.${extension.toUpperCase()}`)
    assert.equal(controller.validateFiles([file]), true, file.name)
  }
  assert.deepEqual(globalThis.uploadFlashes, [])
})

test("unsupported filenames reject the selection with upload.unsupported_type", () => {
  for (const name of ["notes.txt", "photo.heic", "track", "track.gpx.txt"]) {
    const controller = fixture()
    const file = new File(["unsupported"], name, {
      type: "application/gpx+xml",
    })
    assert.equal(
      controller.validateFiles([new File(["track"], "track.gpx"), file]),
      false,
    )
    assert.equal(controller.inputTarget.value, "")
    const [[severity, message]] = globalThis.uploadFlashes
    assert.equal(severity, "error")
    assert.equal(message.key, "upload.unsupported_type")
    assert.equal(message.names, name)
    assert.equal(
      message.accepted,
      extensions.map((ext) => `.${ext}`).join(", "),
    )
  }
})

test("ZIP-only validation accepts an empty MIME type by filename", () => {
  const controller = fixture()
  controller.validateZipValue = true
  assert.equal(
    controller.validateFiles([new File(["archive"], "backup.ZIP")]),
    true,
  )
  assert.deepEqual(globalThis.uploadFlashes, [])
  assert.equal(
    controller.validateFiles([new File(["track"], "track.gpx")]),
    false,
  )
  assert.equal(
    globalThis.uploadFlashes[0][1].key,
    "messages.please_select_a_valid_zip_file",
  )
})

test("empty-type supported files survive upload preparation with their bytes and names", async () => {
  const controller = fixture()
  for (const extension of extensions) {
    const bytes = new Uint8Array([0, 1, 128, 255])
    const original = new File([bytes], `TRACK.${extension.toUpperCase()}`)
    const compress = !["zip", "kmz"].includes(extension)
    assert.equal(shouldZip(original), compress, original.name)
    const prepared = await controller.prepareForUpload([original])
    assert.equal(prepared.length, 1)
    const [upload] = prepared
    assert.equal(upload.originalFilename, original.name)
    assert.equal(upload.clientWrapped, compress)
    if (compress) {
      assert.equal(upload.file.name, `${original.name}.zip`)
      assert.equal(upload.file.type, "application/zip")
      const entries = unzipSync(new Uint8Array(await upload.file.arrayBuffer()))
      assert.deepEqual(Object.keys(entries), [original.name])
      assert.deepEqual(entries[original.name], bytes)
    } else {
      assert.equal(upload.file, original)
      assert.deepEqual(new Uint8Array(await upload.file.arrayBuffer()), bytes)
    }
  }
  assert.deepEqual(globalThis.uploadFlashes, [])
})
