export const Direct = (entries, onViewError) => {
  for (const entry of entries) {
    const xhr = new globalThis.XMLHttpRequest()
    onViewError(() => xhr.abort())
    xhr.onload = () =>
      xhr.status >= 200 && xhr.status < 300
        ? entry.progress(100)
        : entry.error()
    xhr.onerror = () => entry.error()
    xhr.upload.addEventListener("progress", (event) => {
      if (!event.lengthComputable) return
      const percent = Math.round((event.loaded / event.total) * 100)
      if (percent < 100) entry.progress(percent)
    })
    xhr.open("PUT", entry.meta.url, true)
    for (const [key, value] of Object.entries(entry.meta.headers || {}))
      xhr.setRequestHeader(key, value)
    xhr.send(entry.file)
  }
}
