// Hands a rendered MP4 to the backend. The blob goes straight to storage via
// Active Storage's direct upload, then a small Turbo Stream POST creates the
// row from the returned signed id — a 30 MB video never passes through a Rails
// process, and the response prepends the gallery card.
import { DirectUpload } from "@rails/activestorage"

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content ?? ""
}

function uploadBlob(blob, filename, uploadUrl, onProgress) {
  const file = new File([blob], filename, { type: "video/mp4" })

  return new Promise((resolve, reject) => {
    const upload = new DirectUpload(file, uploadUrl, {
      directUploadWillStoreFileWithXHR: (request) => {
        request.upload.addEventListener("progress", (event) => {
          if (event.lengthComputable) onProgress?.(event.loaded / event.total)
        })
      },
    })
    upload.create((error, uploaded) =>
      error ? reject(error) : resolve(uploaded.signed_id),
    )
  })
}

// Resolves to the Turbo Stream markup, which the caller renders. Rejects with
// a message safe to show the user.
export async function saveVideo({
  blob,
  name,
  settings,
  uploadUrl,
  createUrl,
  onProgress,
}) {
  const signedId = await uploadBlob(
    blob,
    `${name || "route-video"}.mp4`,
    uploadUrl,
    onProgress,
  )

  const body = new FormData()
  body.append("route_video[name]", name)
  body.append("route_video[file]", signedId)
  for (const [key, value] of Object.entries(settings)) {
    body.append(`route_video[settings][${key}]`, String(value))
  }

  const response = await fetch(createUrl, {
    method: "POST",
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
