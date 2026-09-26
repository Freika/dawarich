import { zip } from "fflate"

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

const SKIP_EXTENSIONS = new Set(["zip", "kmz", "gz", "tgz"])

export function shouldZip(file) {
  const lower = file.name.toLowerCase()
  if (lower.endsWith(".tar.gz")) return false

  const parts = lower.split(".")
  const ext = parts.length > 1 ? parts.pop() : ""
  return !SKIP_EXTENSIONS.has(ext)
}

export async function prepareFilesForUpload(files, onCompressionFailure) {
  const result = []
  for (const original of files) {
    if (!shouldZip(original)) {
      result.push({
        file: original,
        originalFilename: original.name,
        clientWrapped: false,
      })
      continue
    }
    try {
      const zipped = await zipSingleFile(original)
      result.push({
        file: zipped,
        originalFilename: original.name,
        clientWrapped: true,
      })
    } catch (err) {
      onCompressionFailure(original, err)
      result.push({
        file: original,
        originalFilename: original.name,
        clientWrapped: false,
      })
    }
  }
  return result
}
