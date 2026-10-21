import { miniDocument } from "./mini_dom.mjs"

export function toastDocument() {
  const document = miniDocument()
  const create = document.createElement
  document.createElement = tag => {
    const node = create(tag)
    Object.defineProperty(node, "parentNode", { get: () => node.parent })
    return node
  }
  document.body = document.createElement("body")
  document.head = document.createElement("head")
  document.getElementById = id => document.head.all().find(node => node.id === id)
  return document
}
