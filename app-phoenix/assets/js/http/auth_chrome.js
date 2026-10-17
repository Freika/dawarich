import { initializeAnalyticsEvents } from "../analytics_events.js"
import { initializeHttpCredentialQr } from "./credential_qr.js"

export function initializeAuthChrome(doc = document, win = window) {
  const listeners = [initializeAnalyticsEvents(win)]
  const timers = []
  for (const qr of doc.querySelectorAll("[data-auth-credential-qr]"))
    listeners.push(initializeHttpCredentialQr(qr))
  const listen = (element, event, callback) => {
    element.addEventListener(event, callback)
    listeners.push(() => element.removeEventListener(event, callback))
  }
  for (const flash of doc.querySelectorAll("[data-auth-flash]")) {
    const timeout = Number(flash.dataset.authFlashTimeout)
    if (timeout > 0) timers.push(win.setTimeout(() => flash.remove(), timeout))
  }
  for (const close of doc.querySelectorAll("[data-auth-flash-dismiss]")) {
    listen(close, "click", () => close.closest("[data-auth-flash]")?.remove())
  }
  for (const suggestion of doc.querySelectorAll(
    "[data-auth-locale-suggestion]",
  )) {
    try {
      if (
        win.localStorage.getItem(
          `dismissed:${suggestion.dataset.dismissibleKeyValue}`,
        ) === "1"
      )
        suggestion.remove()
    } catch {}
  }
  for (const dismiss of doc.querySelectorAll("[data-auth-locale-dismiss]")) {
    listen(dismiss, "click", () => {
      const suggestion = dismiss.closest("[data-auth-locale-suggestion]")
      try {
        win.localStorage.setItem(
          `dismissed:${suggestion.dataset.dismissibleKeyValue}`,
          "1",
        )
      } catch {}
      suggestion.remove()
    })
  }
  for (const open of doc.querySelectorAll("[data-auth-open-dialog]")) {
    listen(open, "click", () =>
      doc.getElementById(open.dataset.authOpenDialog)?.showModal(),
    )
  }
  for (const button of doc.querySelectorAll("[data-auth-onboarding-screen]")) {
    listen(button, "click", () => {
      for (const id of [
        "onboarding-choice-screen",
        "onboarding-import-screen",
        "onboarding-track-screen",
      ])
        doc
          .getElementById(id)
          ?.classList.toggle(
            "hidden",
            id !== button.dataset.authOnboardingScreen,
          )
      if (button.dataset.authOnboardingScreen === "onboarding-track-screen")
        doc
          .getElementById("onboarding-api-qr")
          ?.dispatchEvent(new Event("dawarich:http-reveal-qr"))
      if (button.dataset.authTrackEvent)
        win.dispatchEvent(
          new CustomEvent("dawarich:track", {
            detail: { event: button.dataset.authTrackEvent },
          }),
        )
    })
  }
  for (const form of doc.querySelectorAll("form[data-auth-confirm]")) {
    listen(form, "submit", (event) => {
      if (!win.confirm(form.dataset.authConfirm)) event.preventDefault()
    })
  }
  for (const form of doc.querySelectorAll("form[data-auth-track-event]")) {
    listen(form, "submit", () =>
      win.dispatchEvent(
        new CustomEvent("dawarich:track", {
          detail: { event: form.dataset.authTrackEvent },
        }),
      ),
    )
  }
  doc
    .querySelector("[data-auth-settings-navigation] .tab-active")
    ?.scrollIntoView({ block: "nearest", inline: "nearest" })
  return () => {
    for (const remove of listeners) remove()
    for (const timer of timers) win.clearTimeout(timer)
  }
}
