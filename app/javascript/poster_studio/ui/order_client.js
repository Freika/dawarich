import { translate } from "i18n"

const ERROR_KEYS = {
  wrong_size: "poster.order_errors.wrong_size",
  too_large: "poster.order_errors.too_large",
  unknown_sku: "poster.order_errors.unknown_sku",
  payment_unavailable: "poster.order_errors.payment_unavailable",
  not_pdf: "poster.order_errors.not_pdf",
  unreadable: "poster.order_errors.unreadable",
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
      translate(ERROR_KEYS[body.error] || "poster.order_errors.generic"),
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
      reject(new Error(translate("poster.order_errors.connection"))),
    )
    xhr.send(form)
  })
}
