import SparkMD5 from "spark-md5"

export async function base64Md5(
  file,
  { chunkSize = 2 * 1024 * 1024, onProgress = () => {} } = {},
) {
  const md5 = new SparkMD5.ArrayBuffer()
  for (let offset = 0; offset < file.size; offset += chunkSize) {
    md5.append(await file.slice(offset, offset + chunkSize).arrayBuffer())
    onProgress(
      Math.min(100, Math.round(((offset + chunkSize) / file.size) * 100)),
    )
  }
  return btoa(md5.end(true))
}

export const ArchiveChecksum = {
  mounted() {
    this.onChange = (event) => {
      if (event.target.type !== "file") return
      for (const file of event.target.files) this.digest(file)
    }
    this.el.addEventListener("change", this.onChange)
  },
  destroyed() {
    this.el.removeEventListener("change", this.onChange)
  },
  async digest(file) {
    const status = this.el.querySelector("[data-checksum-progress]")
    const checksum = await base64Md5(file, {
      onProgress: (percent) => {
        if (status) status.textContent = `${percent}%`
      },
    })
    this.pushEvent("archive_checksum", { ref: file._phxRef, checksum })
  },
}
