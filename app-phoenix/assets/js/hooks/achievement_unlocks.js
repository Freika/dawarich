const csrf = () =>
  document.querySelector('meta[name="csrf-token"]')?.content || ""

const post = (url, body) =>
  fetch(url, {
    method: "POST",
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrf(),
    },
    body: JSON.stringify(body),
  })

const canReveal = () =>
  !document.hidden && !document.querySelector("dialog[open]")

export class AchievementUnlocksLifecycle {
  constructor(el, material = () => import("../achievements/material.js")) {
    this.el = el
    this.material = material
  }
  start() {
    this.epoch = (this.epoch || 0) + 1
    this.ackPromise = null
    this.stopped = false
    this.current = null
    this.loading = false
    this.transitioning = false
    this.originFocus = document.activeElement
    this.storageKey = `dawarich-achievement-unlock-claim-${this.el.dataset.userId}`
    this.saved = this.readSaved()
    this.batchEndId = this.saved?.batchEndId || null
    this.onKey = (event) => {
      if (event.key === "Escape" && this.el.firstElementChild && canReveal())
        this.dismiss()
    }
    this.onResume = () => {
      if (document.hidden || this.stopped || this.current) return
      clearTimeout(this.retryTimer)
      this.load()
    }
    this.onClick = (event) => {
      const action = event.target.closest("[data-action]")?.dataset.action || ""
      if (action.endsWith("#nextCard")) this.nextCard()
      if (action.endsWith("#dismiss")) this.dismiss()
    }
    window.addEventListener("keydown", this.onKey)
    document.addEventListener("visibilitychange", this.onResume)
    window.addEventListener("pageshow", this.onResume)
    this.el.addEventListener("click", this.onClick)
    this.load()
  }

  stop() {
    this.epoch += 1
    this.stopped = true
    this.release()
    clearTimeout(this.ackTimer)
    clearTimeout(this.retryTimer)
    clearTimeout(this.transitionTimer)
    this.finishTransition?.()
    window.removeEventListener("keydown", this.onKey)
    document.removeEventListener("visibilitychange", this.onResume)
    window.removeEventListener("pageshow", this.onResume)
    this.el.removeEventListener("click", this.onClick)
  }

  async load() {
    if (this.stopped || this.loading) return
    if (!canReveal()) {
      this.retryTimer = this.later(() => this.load(), 1000)
      return
    }
    this.loading = true
    const epoch = this.epoch
    try {
      const response = await post(this.el.dataset.nextUrl, {
        claim_token: this.saved?.token,
        batch_end_id: this.batchEndId,
      })
      if (!this.active(epoch)) return
      if (response.status === 409) {
        this.saved = null
        this.saveClaim()
        this.retryTimer = this.later(() => this.load(), 2000)
        return
      }
      if (
        response.status === 204 ||
        [401, 403, 404].includes(response.status) ||
        response.redirected
      ) {
        this.hide()
        return
      }
      if (!response.ok)
        throw new Error(`Unlock request failed: ${response.status}`)

      const item = await response.json()
      if (!this.active(epoch)) return
      this.current = item
      this.batchEndId = item.batch_end_id
      this.saved = {
        id: item.id,
        token: item.token,
        batchEndId: item.batch_end_id,
      }
      this.saveClaim()
      if (!canReveal()) {
        this.retryTimer = this.later(() => this.load(), 1000)
        return
      }
      this.release()
      this.el.innerHTML = item.html
      await this.decorate(epoch)
      if (!this.active(epoch)) return
      if (this.focusAfterLoad) {
        this.el
          .querySelector(".ach-unlock-front")
          ?.focus({ preventScroll: true })
        this.focusAfterLoad = false
      }
      this.ackTimer = this.later(
        () => this.acknowledge(),
        matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 1100,
      )
    } catch (error) {
      if (this.active(epoch)) {
        console.error(error)
        this.retryTimer = this.later(() => this.load(), 5000)
      }
    } finally {
      if (epoch === this.epoch) this.loading = false
    }
  }

  release() {
    this.dispose?.()
    this.dispose = null
  }

  async decorate(epoch) {
    const { initializeAchievementMaterials: initialize } = await this.material()
    if (this.active(epoch)) this.dispose = initialize(this.el)
  }

  async nextCard() {
    if (this.stopped || !this.current || this.transitioning) return
    const epoch = this.epoch
    this.transitioning = true
    clearTimeout(this.ackTimer)
    const acknowledged = await this.acknowledge()
    if (!this.active(epoch)) return
    if (!acknowledged) {
      this.transitioning = false
      return
    }
    if (this.current.remaining <= 1) {
      this.hide()
      this.restoreFocus()
    } else {
      this.el.firstElementChild?.classList.add("ach-unlock-reveal--leaving")
      await new Promise((resolve) => {
        this.finishTransition = resolve
        this.transitionTimer = setTimeout(resolve, 170)
      })
      if (!this.active(epoch)) return
      this.finishTransition = null
      this.focusAfterLoad = true
      await this.load()
      if (!this.active(epoch)) return
      if (!this.current) this.restoreFocus()
    }
    this.transitioning = false
  }

  async dismiss() {
    if (this.stopped || !this.current || this.transitioning) return
    const epoch = this.epoch
    this.transitioning = true
    clearTimeout(this.ackTimer)
    try {
      const response = await post(this.el.dataset.dismissUrl, {
        batch_end_id: this.batchEndId,
      })
      if (!this.active(epoch)) return
      if (!response.ok)
        throw new Error(`Unlock dismiss failed: ${response.status}`)
      this.hide()
      this.restoreFocus()
    } catch (error) {
      if (this.active(epoch)) console.error(error)
    } finally {
      if (this.active(epoch)) this.transitioning = false
    }
  }

  acknowledge() {
    if (this.stopped) return Promise.resolve(false)
    if (!this.current?.token) return Promise.resolve(true)
    if (!canReveal()) {
      this.ackTimer = this.later(() => this.acknowledge(), 1000)
      return Promise.resolve(false)
    }
    if (this.ackPromise) return this.ackPromise
    const epoch = this.epoch
    const item = this.current
    const url = this.el.dataset.seenUrl.replace("__ID__", String(item.id))
    this.ackPromise = post(url, { claim_token: item.token })
      .then((response) => {
        if (!this.active(epoch)) return false
        if (!response.ok && response.status !== 409)
          throw new Error(`Unlock acknowledgement failed: ${response.status}`)
        item.token = null
        this.saved = null
        this.saveClaim()
        return true
      })
      .catch((error) => {
        if (!this.active(epoch)) return false
        console.error(error)
        if (!this.stopped)
          this.retryTimer = this.later(() => this.acknowledge(), 5000)
        return false
      })
      .finally(() => {
        if (this.active(epoch)) this.ackPromise = null
      })
    return this.ackPromise
  }

  active(epoch) {
    return !this.stopped && epoch === this.epoch
  }

  later(action, delay) {
    const epoch = this.epoch
    return setTimeout(() => {
      if (this.active(epoch)) action()
    }, delay)
  }

  hide() {
    this.release()
    clearTimeout(this.ackTimer)
    clearTimeout(this.retryTimer)
    this.current = null
    this.saved = null
    this.batchEndId = null
    this.focusAfterLoad = false
    this.saveClaim()
    this.el.replaceChildren()
  }

  restoreFocus() {
    if (this.originFocus?.isConnected)
      this.originFocus.focus({ preventScroll: true })
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
    } catch {}
  }
}

export function initializeAchievementUnlocks(el) {
  const runtime = new AchievementUnlocksLifecycle(el)
  runtime.start()
  return () => runtime.stop()
}

export const AchievementUnlocks = {
  mounted() {
    this.dispose = initializeAchievementUnlocks(this.el)
  },
  destroyed() {
    this.dispose?.()
  },
}
