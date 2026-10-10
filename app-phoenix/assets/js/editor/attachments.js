import { base64Md5 } from "../hooks/archive_checksum.js"

export function putFile(url, headers, file, onProgress) {
  const xhr = new globalThis.XMLHttpRequest()
  const done = new Promise((resolve, reject) => {
    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300 ? resolve() : reject()
    xhr.onerror = () => reject()
    xhr.onabort = () => reject()
    xhr.upload.addEventListener("progress", (event) => {
      if (event.lengthComputable)
        onProgress(Math.round((event.loaded / event.total) * 100))
    })
    xhr.open("PUT", url, true)
    for (const [key, value] of Object.entries(headers || {}))
      xhr.setRequestHeader(key, value)
    xhr.send(file)
  })
  return { done, abort: () => xhr.abort() }
}

export class RichAttachments {
  constructor(hook, { digest = base64Md5, transport = putFile } = {}) {
    this.hook = hook
    this.digest = digest
    this.transport = transport
    this.pending = new Set()
  }

  async add(attachment) {
    const file = attachment.file
    if (!file) return
    const token = { attachment, cancelled: false }
    this.pending.add(token)
    this.status("")
    attachment.setUploadProgress(0)
    try {
      const checksum = await this.digest(file)
      const target = await this.push(token, "rich_upload_reserve", {
        name: file.name,
        size: file.size,
        type: file.type,
        checksum,
      })
      token.ref = target.upload_ref
      token.upload = this.transport(target.url, target.headers, file, (n) =>
        this.live(token) ? attachment.setUploadProgress(Math.min(n, 99)) : null,
      )
      await token.upload.done
      const claimed = await this.push(token, "rich_upload_claim", {
        upload_ref: token.ref,
      })
      if (!this.live(token)) return
      attachment.setAttributes({
        sgid: claimed.sgid,
        url: claimed.url,
        href: claimed.href,
      })
      attachment.setUploadProgress(100)
      this.pending.delete(token)
    } catch (_error) {
      if (this.live(token)) this.fail(token)
    }
  }

  push(token, event, payload) {
    return new Promise((resolve, reject) => {
      if (!this.live(token)) return reject(new Error("cancelled"))
      this.hook.pushEvent(event, payload, (reply) =>
        this.live(token) && reply && !reply.error
          ? resolve(reply)
          : reject(new Error("refused")),
      )
    })
  }

  remove(attachment) {
    for (const token of this.pending)
      if (token.attachment === attachment) this.cancel(token, true)
  }

  cancelAll() {
    for (const token of this.pending) this.cancel(token, false)
  }

  cancel(token, notify) {
    token.cancelled = true
    this.pending.delete(token)
    token.upload?.abort()
    if (notify && token.ref && this.hook.alive)
      this.hook.pushEvent("rich_upload_cancel", { upload_ref: token.ref })
  }

  fail(token) {
    this.pending.delete(token)
    token.attachment.remove()
    this.status(this.hook.el.dataset.uploadFailed || "")
  }

  live(token) {
    return !token.cancelled && this.hook.alive && this.pending.has(token)
  }

  status(text) {
    const element = this.hook.statusElement?.()
    if (element) element.textContent = text
  }
}
