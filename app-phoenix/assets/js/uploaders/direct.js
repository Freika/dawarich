const csrf = () =>
  globalThis.document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute("content")
const request = (action, ref, signal) =>
  globalThis.fetch(`/native/uploads/${action}`, {
    method: "POST",
    credentials: "same-origin",
    cache: "no-store",
    keepalive: action === "cancel",
    signal,
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": csrf(),
      Accept: "application/json",
    },
    body: JSON.stringify({ upload_ref: ref }),
  })

export const Direct = (entries, onViewError) => {
  for (const entry of entries) {
    const controller = new AbortController()
    let xhr,
      timer,
      loaded = 0,
      stopped = false
    const clear = () => {
      clearTimeout(timer)
      if (xhr) {
        xhr.onload = xhr.onerror = null
        xhr.upload.removeEventListener?.("progress", progress)
      }
    }
    const cancel = () => {
      if (stopped) return
      stopped = true
      controller.abort()
      clear()
      xhr?.abort()
      xhr = null
      request("cancel", entry.meta.upload_ref).catch(() => {})
    }
    const fail = (stage) => {
      if (!stopped) {
        cancel()
        entry.fileEl?.dispatchEvent(
          new CustomEvent("dawarich:upload-error", {
            bubbles: true,
            detail: { stage },
          }),
        )
        entry.error(stage)
      }
    }
    const idle = () => {
      clearTimeout(timer)
      timer = setTimeout(
        () => fail("timeout"),
        Number(entry.fileEl?.dataset.idleTimeout || 120) * 1000,
      )
    }
    const progress = (event) => {
      if (stopped || entry.isCancelled?.()) return
      if (!event.lengthComputable || event.loaded <= loaded) return
      loaded = event.loaded
      idle()
      const percent = Math.round((event.loaded * 100) / event.total)
      if (percent < 100) entry.progress(percent)
    }
    entry.onCancel?.(cancel)
    onViewError(cancel)
    idle()
    request("target", entry.meta.upload_ref, controller.signal)
      .then((response) => {
        if (!response.ok) throw new Error("Target refused")
        return response.json()
      })
      .then((target) => {
        if (stopped || controller.signal.aborted || entry.isCancelled?.())
          return
        xhr = new globalThis.XMLHttpRequest()
        xhr.onload = () => {
          if (stopped || entry.isCancelled?.()) return
          if (xhr.status < 200 || xhr.status >= 300) return fail("upload")
          clear()
          xhr = null
          entry.progress(100)
        }
        xhr.onerror = () => fail("upload")
        xhr.upload.addEventListener("progress", progress)
        xhr.open("PUT", target.url, true)
        for (const [key, value] of Object.entries(target.headers || {}))
          xhr.setRequestHeader(key, value)
        target = null
        xhr.send(entry.file)
      })
      .catch(() => {
        if (!stopped) fail("target")
      })
  }
}
