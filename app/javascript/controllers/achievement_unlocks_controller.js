import { Controller } from "@hotwired/stimulus"

// A small, durable inbox for newly earned cards. Fetch one front card at a
// time so a large import never mounts a gallery of foil effects in the corner.
export default class extends Controller {
  static values = {
    nextUrl: String,
    seenUrl: String,
    dismissUrl: String,
    userId: Number,
  }

  connect() {
    this.generation = (this.generation || 0) + 1
    this.stopped = false
    this.current = null
    this.loading = false
    this.transitioning = false
    this.originFocus = document.activeElement
    this.storageKey = `dawarich-achievement-unlock-claim-${this.userIdValue}`
    this.saved = this.readSaved()
    this.batchEndId = this.saved?.batchEndId || null
    this.load()
  }

  disconnect() {
    this.generation += 1
    this.stopped = true
    clearTimeout(this.ackTimer)
    clearTimeout(this.retryTimer)
  }

  beforeCache() {
    clearTimeout(this.ackTimer)
    this.element.replaceChildren()
  }

  keyDown(event) {
    if (
      event.key === "Escape" &&
      this.element.firstElementChild &&
      this.canReveal()
    )
      this.dismiss()
  }

  resumeVisit() {
    if (document.hidden || this.stopped || this.current) return
    clearTimeout(this.retryTimer)
    return this.load()
  }

  async load() {
    if (this.stopped || this.loading) return
    if (!this.canReveal()) {
      this.retryTimer = setTimeout(() => this.load(), 1000)
      return
    }
    this.loading = true
    const generation = this.generation
    try {
      const response = await this.post(this.nextUrlValue, {
        claim_token: this.saved?.token,
        batch_end_id: this.batchEndId,
      })
      if (this.stopped || generation !== this.generation) return
      if (response.status === 409) {
        this.saved = null
        this.saveClaim()
        this.retryTimer = setTimeout(() => this.load(), 2000)
        return
      }
      if (response.status === 204) {
        this.hide()
        return
      }
      if ([401, 403, 404].includes(response.status) || response.redirected) {
        this.hide()
        return
      }
      if (!response.ok)
        throw new Error(`Unlock request failed: ${response.status}`)

      const item = await response.json()
      if (this.stopped || generation !== this.generation) return
      this.current = item
      this.batchEndId = item.batch_end_id
      this.saved = {
        id: item.id,
        token: item.token,
        batchEndId: item.batch_end_id,
      }
      this.saveClaim()
      if (!this.canReveal()) {
        this.retryTimer = setTimeout(() => this.load(), 1000)
        return
      }
      this.element.innerHTML = item.html
      if (this.focusAfterLoad) {
        this.element
          .querySelector?.(".ach-unlock-front")
          ?.focus({ preventScroll: true })
        this.focusAfterLoad = false
      }
      this.ackTimer = setTimeout(
        () => this.acknowledge(),
        matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 1100,
      )
    } catch (error) {
      if (!this.stopped && generation === this.generation) {
        console.error(error)
        this.retryTimer = setTimeout(() => this.load(), 5000)
      }
    } finally {
      if (generation === this.generation) this.loading = false
    }
  }

  async nextCard() {
    if (!this.current || this.transitioning) return
    this.transitioning = true
    clearTimeout(this.ackTimer)
    if (!(await this.acknowledge())) {
      this.transitioning = false
      return
    }
    if (this.current.remaining <= 1) {
      this.hide()
      this.restoreFocus()
    } else {
      this.element.firstElementChild?.classList.add(
        "ach-unlock-reveal--leaving",
      )
      await new Promise((resolve) => setTimeout(resolve, 170))
      this.focusAfterLoad = true
      await this.load()
      if (!this.current) this.restoreFocus()
    }
    this.transitioning = false
  }

  async dismiss() {
    if (!this.current || this.transitioning) return
    this.transitioning = true
    clearTimeout(this.ackTimer)
    try {
      const response = await this.post(this.dismissUrlValue, {
        batch_end_id: this.batchEndId,
      })
      if (!response.ok)
        throw new Error(`Unlock dismiss failed: ${response.status}`)
      this.hide()
      this.restoreFocus()
    } catch (error) {
      console.error(error)
      this.transitioning = false
    }
  }

  acknowledge() {
    if (!this.current?.token) return Promise.resolve(true)
    if (!this.canReveal()) {
      this.ackTimer = setTimeout(() => this.acknowledge(), 1000)
      return Promise.resolve(false)
    }
    if (this.ackPromise) return this.ackPromise
    const item = this.current
    const url = this.seenUrlValue.replace("__ID__", String(item.id))
    this.ackPromise = this.post(url, { claim_token: item.token })
      .then((response) => {
        if (!response.ok)
          throw new Error(`Unlock acknowledgement failed: ${response.status}`)
        item.token = null
        this.saved = null
        this.saveClaim()
        return true
      })
      .catch((error) => {
        console.error(error)
        this.retryTimer = setTimeout(() => this.acknowledge(), 5000)
        return false
      })
      .finally(() => {
        this.ackPromise = null
      })
    return this.ackPromise
  }

  hide() {
    clearTimeout(this.ackTimer)
    clearTimeout(this.retryTimer)
    this.current = null
    this.saved = null
    this.batchEndId = null
    this.focusAfterLoad = false
    this.saveClaim()
    this.element.replaceChildren()
  }

  canReveal() {
    return !document.hidden && !document.querySelector("dialog[open]")
  }

  restoreFocus() {
    if (this.originFocus?.isConnected)
      this.originFocus.focus({ preventScroll: true })
  }

  post(url, body) {
    return fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token":
          document.querySelector('meta[name="csrf-token"]')?.content || "",
      },
      body: JSON.stringify(body),
    })
  }

  readSaved() {
    try {
      return JSON.parse(sessionStorage.getItem(this.storageKey))
    } catch {
      return null
    }
  }

  saveClaim() {
    try {
      if (this.saved)
        sessionStorage.setItem(this.storageKey, JSON.stringify(this.saved))
      else sessionStorage.removeItem(this.storageKey)
    } catch {
      // Private browsing may deny storage; the server lease still expires.
    }
  }
}
