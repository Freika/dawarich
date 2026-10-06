import { DirectUpload } from "@rails/activestorage"

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
}

function uploadBlob(blob, filename, uploadUrl, onProgress, signal) {
  const file = new File([blob], filename, { type: "video/mp4" })
  return new Promise((resolve, reject) => {
    let settled = false
    const requests = new Set()
    const listeners = []
    const cleanup = () => {
      signal?.removeEventListener("abort", abort)
      for (const [target, callback] of listeners)
        target.removeEventListener("progress", callback)
    }
    const finish = (error, uploaded) => {
      if (settled) return
      settled = true
      cleanup()
      if (error) reject(error)
      else resolve(uploaded.signed_id)
    }
    const abort = () => {
      finish(new DOMException("Upload cancelled", "AbortError"))
      for (const request of requests) request.abort()
    }
    if (signal?.aborted) return abort()
    signal?.addEventListener("abort", abort, { once: true })
    const upload = new DirectUpload(file, uploadUrl, {
      directUploadWillCreateBlobWithXHR: (request) => requests.add(request),
      directUploadWillStoreFileWithXHR: (request) => {
        requests.add(request)
        const progress = (event) => {
          if (!settled && event.lengthComputable)
            onProgress?.(event.loaded / event.total)
        }
        request.upload.addEventListener("progress", progress)
        listeners.push([request.upload, progress])
      },
    })
    try {
      upload.create(finish)
    } catch (error) {
      finish(error)
    }
  })
}

export async function saveVideo({
  blob,
  name,
  settings,
  uploadUrl,
  createUrl,
  onProgress,
  signal,
}) {
  const signedId = await uploadBlob(
    blob,
    `${name || "route-video"}.mp4`,
    uploadUrl,
    onProgress,
    signal,
  )
  signal?.throwIfAborted()

  const body = new FormData()
  body.append("route_video[name]", name)
  body.append("route_video[file]", signedId)
  for (const [key, value] of Object.entries(settings)) {
    body.append(`route_video[settings][${key}]`, String(value))
  }

  const response = await fetch(createUrl, {
    method: "POST",
    signal,
    body,
    headers: {
      "X-CSRF-Token": csrfToken(),
      Accept: "text/vnd.turbo-stream.html",
    },
  })

  const stream = await response.text()
  if (!response.ok && !stream.includes("turbo-stream")) {
    throw new Error(`Save failed (${response.status})`)
  }
  return stream
}
