import { zip } from "fflate"

// Wraps a single File in a zip archive using fflate's async API,
// which runs compression off the main thread internally.
// Resolves to a new File with name `<original>.zip` and type application/zip.
// Rejects with the underlying error if fflate cannot produce a zip.
export async function zipSingleFile(file) {
  const bytes = new Uint8Array(await file.arrayBuffer())

  const zipped = await new Promise((resolve, reject) => {
    zip({ [file.name]: bytes }, { level: 6 }, (err, data) => {
      if (err) reject(err)
      else resolve(data)
    })
  })

  return new File([zipped], `${file.name}.zip`, { type: "application/zip" })
}

// .zip is already a zip. .kmz is also a zip container (KML inside a zip) —
// re-zipping would just add an outer wrapper for no compression benefit.
const SKIP_EXTENSIONS = new Set(["zip", "kmz"])

export function shouldZip(file) {
  const parts = file.name.toLowerCase().split(".")
  const ext = parts.length > 1 ? parts.pop() : ""
  return !SKIP_EXTENSIONS.has(ext)
}
