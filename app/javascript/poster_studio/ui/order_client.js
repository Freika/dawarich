const ERROR_MESSAGES = {
  wrong_size: "The exported PDF doesn't match the selected format — try again.",
  too_large:
    "The exported PDF is too large (50 MB max). Lower the DPI cap or zoom out.",
  unknown_sku: "This format is not orderable right now.",
  payment_unavailable:
    "Payment is temporarily unavailable — try again in a minute.",
  not_pdf: "The export didn't produce a valid PDF — try again.",
  unreadable: "The exported PDF couldn't be read — try again.",
}

export async function submitPrintOrder({
  url,
  blob,
  sku,
  title,
  themeBase,
  layoutId,
  onProgress,
}) {
  const form = new FormData()
  form.append("file", blob, "poster.pdf")
  form.append("sku", sku)
  form.append("title", title || "")
  form.append("theme_base", themeBase || "")
  form.append("layout_id", layoutId)

  const { status, body } = await postForm(url, form, onProgress)
  if (status < 200 || status >= 300) {
    throw new Error(
      ERROR_MESSAGES[body.error] || "Order upload failed — try again.",
    )
  }
  return { token: body.token, checkoutUrl: body.checkout_url }
}

// XMLHttpRequest instead of fetch solely for upload progress events —
// print PDFs run tens of MB and fetch has no upload progress API.
function postForm(url, form, onProgress) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open("POST", url)
    xhr.responseType = "json"
    if (onProgress) {
      xhr.upload.addEventListener("progress", (event) => {
        if (event.lengthComputable) onProgress(event.loaded / event.total)
      })
    }
    xhr.addEventListener("load", () =>
      resolve({ status: xhr.status, body: xhr.response || {} }),
    )
    xhr.addEventListener("error", () =>
      reject(
        new Error("Could not reach the order service — check your connection."),
      ),
    )
    xhr.send(form)
  })
}
