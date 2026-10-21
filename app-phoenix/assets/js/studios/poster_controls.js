import { studioQuery } from "./dom.js"
import { PRINT_PRODUCTS } from "../poster/data/print_products.js"

export function populatePosterControls(root, config) {
  if (!root.dataset.nativeStudio) return
  const doc = root.ownerDocument
  const find = (name) => studioQuery(root, `[data-poster-${name}]`)
  const option = ({ value, label }) => {
    const node = doc.createElement("option")
    node.value = value
    node.textContent = label
    return node
  }
  const layout = find("layout")
  if (layout && !layout.children.length) {
    for (const group of config.controls.layouts) {
      const node = doc.createElement("optgroup")
      node.label = group.label
      node.append(...group.options.map(option))
      layout.append(node)
    }
  }
  const font = find("font")
  if (font && !font.children.length) font.append(...config.controls.fonts.map(option))
  const sizes = find("size-options")
  if (sizes && !sizes.children.length) {
    for (const { value, label } of config.controls.sizes) {
      const button = doc.createElement("button")
      button.type = "button"
      button.className = "btn btn-ghost btn-sm w-full justify-between"
      button.dataset.nativePosterPrintSize = value
      const name = doc.createElement("span")
      name.textContent = label
      const price = doc.createElement("span")
      price.textContent = PRINT_PRODUCTS[value].priceLabel
      button.append(name, price)
      sizes.append(button)
    }
  }
}
