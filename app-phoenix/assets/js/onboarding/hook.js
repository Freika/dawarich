import { createOnboardingDialog } from "./dialog.js"

export const OnboardingHook = {
  mounted() {
    this.owner = createOnboardingDialog({
      dialog: this.el,
      auto: this.el.dataset.nativeAuto === "true",
      userId: this.el.dataset.nativeUserId,
      complete: () => this.pushEventTo(this.el, "onboarding:complete", {}),
    })
    this.owner.start()
  },
  destroyed() {
    this.owner?.destroy()
  },
}
