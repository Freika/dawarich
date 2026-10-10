import { base64Md5 } from "../hooks/archive_checksum.js"

const aborted = () => new DOMException("Upload cancelled", "AbortError")

function refused(reply, code) {
  const error = new Error(reply?.error || code)
  error.code = code
  return error
}

function put(target, file, { XMLHttpRequest: Xhr, signal, onProgress }) {
  return new Promise((resolve, reject) => {
    const xhr = new Xhr()
    const listeners = []
    const listen = (emitter, type, fn) => {
      emitter.addEventListener(type, fn)
      listeners.push([emitter, type, fn])
    }
    const settle = (finish, value) => {
      for (const [emitter, type, fn] of listeners)
        emitter.removeEventListener(type, fn)
      signal?.removeEventListener("abort", cancel)
      finish(value)
    }
    const cancel = () => xhr.abort()
    listen(xhr, "load", () =>
      xhr.status >= 200 && xhr.status < 300
        ? settle(resolve)
        : settle(reject, refused(null, "upload_failed")),
    )
    listen(xhr, "error", () => settle(reject, refused(null, "upload_failed")))
    listen(xhr, "abort", () => settle(reject, aborted()))
    listen(xhr.upload, "progress", (event) => {
      if (event.lengthComputable) onProgress?.(event.loaded / event.total)
    })
    signal?.addEventListener("abort", cancel, { once: true })
    xhr.open("PUT", target.url, true)
    for (const [key, value] of Object.entries(target.headers ?? {}))
      xhr.setRequestHeader(key, value)
    xhr.send(file)
  })
}

export async function uploadRenderedVideo({
  blob,
  name,
  settings,
  request,
  signal,
  onProgress,
  XMLHttpRequest = globalThis.XMLHttpRequest,
  checksum = base64Md5,
}) {
  if (signal?.aborted) throw aborted()
  const filename = `${name || "route-video"}.mp4`
  const file = new File([blob], filename, { type: "video/mp4" })
  const digest = await checksum(file)
  if (signal?.aborted) throw aborted()

  const target = await request("video:upload_target", {
    byte_size: file.size,
    checksum: digest,
    filename,
  })
  if (!target?.ok) throw refused(target, "upload_refused")

  try {
    await put(target, file, { XMLHttpRequest, signal, onProgress })
    if (signal?.aborted) throw aborted()
  } catch (error) {
    await request("video:discard", { signed_id: target.signed_id }).catch(
      () => null,
    )
    throw error
  }

  const saved = await request("video:save", {
    signed_id: target.signed_id,
    name,
    settings: Object.fromEntries(
      Object.entries(settings ?? {}).map(([key, value]) => [
        key,
        String(value),
      ]),
    ),
  })
  if (!saved?.ok) throw refused(saved, "save_failed")
  return saved
}
