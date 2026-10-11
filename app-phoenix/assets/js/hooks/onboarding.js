import { createOnboardingDialog } from "../onboarding/dialog.js"

export const OnboardingHook = {
  mounted() {
    this.owner = createOnboardingDialog({
      dialog: this.el,
      auto: this.el.dataset.auto === "true",
      userId: this.el.dataset.userId,
      complete: () => this.pushEventTo(this.el, "onboarding:complete", {}),
    })
    this.owner.start()
  },
  destroyed() {
    this.owner?.destroy()
  },
}
