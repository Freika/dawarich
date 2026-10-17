const check = (signal) => {
  if (signal?.aborted) throw new DOMException("Aborted", "AbortError")
}

export async function base64Md5(
  file,
  {
    chunkSize = 2 * 1024 * 1024,
    onProgress = () => {},
    signal,
    loadMd5 = () => import("spark-md5"),
  } = {},
) {
  check(signal)
  const { default: SparkMD5 } = await loadMd5()
  check(signal)
  const md5 = new SparkMD5.ArrayBuffer()
  for (let offset = 0; offset < file.size; offset += chunkSize) {
    check(signal)
    const bytes = await file.slice(offset, offset + chunkSize).arrayBuffer()
    check(signal)
    md5.append(bytes)
    onProgress(
      Math.min(100, Math.round(((offset + chunkSize) / file.size) * 100)),
    )
  }
  check(signal)
  return btoa(md5.end(true))
}

export const ArchiveChecksum = {
  mounted() {
    this.generation = 0
    this.controllers = new Set()
    this.onChange = (event) => {
      if (event.target.type !== "file") return
      if (event.target.hasAttribute?.("data-native-selection"))
        this.select(event.target.files)
      else for (const file of event.target.files) this.digest(file)
    }
    this.onCancel = (event) => {
      if (
        event.target.closest?.(
          "[phx-click='cancel_archive'],[phx-click='cancel_upload']",
        )
      )
        this.abort()
    }
    this.onError = (event) =>
      this.pushEvent("upload_preparation_error", { stage: event.detail.stage })
    this.el.addEventListener("dawarich:upload-error", this.onError)
    this.el.addEventListener("change", this.onChange)
    this.el.addEventListener("click", this.onCancel)
  },
  abort() {
    this.generation++
    for (const controller of this.controllers) controller.abort()
    this.controllers.clear()
  },
  disconnected() {
    this.abort()
  },
  destroyed() {
    this.abort()
    this.el.removeEventListener("dawarich:upload-error", this.onError)
    this.el.removeEventListener("change", this.onChange)
    this.el.removeEventListener("click", this.onCancel)
  },
  async digest(file) {
    const controller = new AbortController()
    this.controllers.add(controller)
    const generation = this.generation
    const ref = file._phxRef
    try {
      const status = this.el.querySelector("[data-checksum-progress]")
      const checksum = await base64Md5(file, {
        signal: controller.signal,
        onProgress: (percent) => {
          if (status && generation === this.generation)
            status.textContent = `${percent}%`
        },
      })
      if (!controller.signal.aborted && generation === this.generation)
        this.pushEvent("archive_checksum", { ref, checksum })
    } catch (error) {
      if (error.name !== "AbortError")
        this.pushEvent("upload_preparation_error", { stage: "checksum" })
    } finally {
      this.controllers.delete(controller)
    }
  },
  async select(files) {
    this.abort()
    const generation = this.generation
    const controller = new AbortController()
    this.controllers.add(controller)
    const options = { signal: controller.signal }
    const prepared = []
    let retained = 0
    const status = this.el.querySelector("[data-checksum-progress]")
    const report = (index, fraction) => {
      if (status && generation === this.generation)
        status.textContent = `${Math.round(((index + fraction) / files.length) * 100)}%`
    }
    try {
      const maxEntries = Number(this.el.dataset.maxEntries) || 20
      if (files.length > maxEntries) {
        this.pushEvent("upload_selection_error", { kind: "too_many_files" })
        return
      }
      for (const [index, file] of Array.from(files).entries()) {
        let item = {
          file,
          originalFilename: file.name,
          originalSize: file.size,
          clientWrapped: false,
        }
        if (this.el.dataset.uploadKind === "imports") {
          const { prepareFile } = await import("../uploads/prepare_file.js")
          item = await prepareFile(file, {
            ...options,
            maxOriginal:
              Number(this.el.dataset.preparationOriginalBytes) || undefined,
            maxWorking:
              (Number(this.el.dataset.preparationBytes) || 64 * 1024 * 1024) -
              retained * 3,
            onProgress: (percent) => report(index, percent / 200),
          })
        }
        report(index, 0.5)
        let checksum
        try {
          checksum = await base64Md5(item.file, {
            ...options,
            onProgress: (percent) => report(index, 0.5 + percent / 200),
          })
        } catch (error) {
          if (error.name !== "AbortError")
            this.pushEvent("upload_preparation_error", { stage: "checksum" })
          return
        }
        check(controller.signal)
        if (generation !== this.generation) return
        item.file.meta = () => ({
          checksum,
          original_filename: item.originalFilename,
          original_size: item.originalSize,
          client_wrapped: item.clientWrapped,
        })
        prepared.push(item.file)
        if (item.clientWrapped) retained += item.file.size
        if (item.fallback)
          this.pushEvent("upload_preparation_fallback", {
            kind: item.fallback,
            filename: file.name,
          })
      }
      check(controller.signal)
      if (generation === this.generation)
        this.upload(this.el.dataset.uploadName, prepared)
    } catch (error) {
      if (error.name !== "AbortError")
        this.pushEvent("upload_preparation_error", { stage: "preparation" })
    } finally {
      this.controllers.delete(controller)
    }
  },
}
