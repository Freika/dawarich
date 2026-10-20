export function lazyFeature(name, events = [], load = () => import("./achievement_family_runtime.js")) {
  return {
    async mounted() {
      const queued = []
      const hold = (event) => { event.preventDefault(); queued.push(event) }
      this.release = () => events.forEach(([type]) => this.el.removeEventListener(type, hold))
      events.forEach(([type]) => this.el.addEventListener(type, hold))
      const feature = (await load())[name]
      this.release()
      if (this.departed) return
      Object.assign(this, feature)
      await this.mounted()
      for (const event of queued)
        if (this.el.contains(event.target)) this[events.find(([type]) => type === event.type)[1]](event)
    },
    destroyed() { this.departed = true; this.release?.() },
  }
}

export const FamilySharing = lazyFeature("FamilySharing", [["change", "change"], ["submit", "submit"]])
export const FamilyInviteScroll = lazyFeature("FamilyInviteScroll", [["click", "scroll"]])
export const AchievementClipboard = lazyFeature("AchievementClipboard", [["click", "copy"]])
export const AchievementMaterial = lazyFeature("AchievementMaterial")
