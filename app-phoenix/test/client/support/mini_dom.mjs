class ClassList {
  constructor(element) {
    this.element = element
  }
  get set() {
    return new Set(
      (this.element.attributes.class || "").split(/\s+/).filter(Boolean),
    )
  }
  contains(name) {
    return this.set.has(name)
  }
  add(...names) {
    const set = this.set
    for (const name of names) set.add(name)
    this.element.attributes.class = [...set].join(" ")
  }
  remove(...names) {
    const set = this.set
    for (const name of names) set.delete(name)
    this.element.attributes.class = [...set].join(" ")
  }
  toggle(name, force) {
    const on = force ?? !this.contains(name)
    if (on) this.add(name)
    else this.remove(name)
    return on
  }
}

class Element {
  constructor(tag) {
    this.tagName = tag.toUpperCase()
    this.attributes = {}
    this.children = []
    this.listeners = {}
    this.text = ""
    this.classList = new ClassList(this)
    this.style = {}
    this.dataset = {}
  }
  get className() {
    return this.attributes.class || ""
  }
  set className(value) {
    this.attributes.class = value
  }
  get textContent() {
    return this.text + this.children.map((child) => child.textContent).join("")
  }
  set textContent(value) {
    this.text = String(value)
    this.children = []
  }
  setAttribute(name, value) {
    this.attributes[name] = String(value)
    if (name.startsWith("data-"))
      this.dataset[name.slice(5).replace(/-(\w)/g, (_, c) => c.toUpperCase())] =
        String(value)
  }
  getAttribute(name) {
    return this.attributes[name] ?? null
  }
  append(...nodes) {
    for (const node of nodes)
      if (typeof node === "string") this.text += node
      else this.children.push(node)
  }
  appendChild(node) {
    this.append(node)
    return node
  }
  replaceChildren(...nodes) {
    this.children = []
    this.text = ""
    this.append(...nodes)
  }
  addEventListener(name, fn) {
    ;(this.listeners[name] ??= []).push(fn)
  }
  removeEventListener(name, fn) {
    this.listeners[name] = (this.listeners[name] ?? []).filter((f) => f !== fn)
  }
  dispatch(name, event = {}) {
    for (const fn of this.listeners[name] ?? [])
      fn({
        preventDefault() {},
        stopPropagation() {},
        currentTarget: this,
        target: this,
        ...event,
      })
  }
  click() {
    this.dispatch("click")
  }
  all() {
    return this.children.flatMap((child) => [child, ...child.all()])
  }
  querySelectorAll(selector) {
    const cls = selector.startsWith(".") ? selector.slice(1) : null
    return this.all().filter((node) =>
      cls
        ? node.classList.contains(cls)
        : node.tagName === selector.toUpperCase(),
    )
  }
  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null
  }
}

export function miniDocument() {
  return { createElement: (tag) => new Element(tag) }
}
