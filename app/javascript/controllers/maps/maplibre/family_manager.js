import { formatTime, translate } from "i18n"
import { Toast } from "maps_maplibre/components/toast"

/** The family members list, their markers and their shared history lines. */
export class FamilyManager {
  constructor(controller) {
    this.controller = controller
    this.memberCount = 0
    this._historyTimer = null
  }

  disconnect() {
    clearTimeout(this._historyTimer)
  }

  debouncedLoadHistory() {
    clearTimeout(this._historyTimer)
    this._historyTimer = setTimeout(() => this.loadHistory(), 300)
  }

  async loadMembers() {
    try {
      this.controller.showProgress()
      this.controller.updateLoadingCounts({
        counts: { family: 0 },
        isComplete: false,
      })

      const response = await fetch("/api/v1/families/locations", {
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          Authorization: `Bearer ${this.controller.apiKeyValue}`,
        },
      })

      if (!response.ok) {
        if (response.status === 403) {
          Toast.info(translate("messages.family_feature_not_available"))
          this.controller.updateLoadingCounts({
            counts: { family: 0 },
            isComplete: true,
          })
          return
        }
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      const locations = data.locations || []

      // Update family layer with locations
      const familyLayer = this.controller.layerManager.getLayer("family")
      if (familyLayer) {
        familyLayer.loadMembers(locations)
      }

      // Update family count in badge
      this.memberCount = locations.length
      this.controller.updateLoadingCounts({
        counts: { family: locations.length },
        isComplete: true,
      })

      // Render family members list
      this.renderMembersList(locations)

      Toast.success(
        translate("family.loaded_members", { count: locations.length }),
      )

      // Load history polylines
      this.loadHistory()
    } catch (error) {
      console.error("[Maps V2] Failed to load family members:", error)
      Toast.error(translate("messages.failed_to_load_family_members"))
    }
  }

  async loadHistory() {
    try {
      const startAt = this.controller.startDateValue
      const endAt = this.controller.endDateValue
      if (!startAt || !endAt) return

      const params = new URLSearchParams({ start_at: startAt, end_at: endAt })
      const response = await fetch(
        `/api/v1/families/locations/history?${params}`,
        {
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
            Authorization: `Bearer ${this.controller.apiKeyValue}`,
          },
        },
      )

      if (!response.ok) return

      const data = await response.json()
      const members = data.members || []

      const familyLayer = this.controller.layerManager.getLayer("family")
      if (familyLayer) {
        if (members.length > 0) {
          // Assign colors consistent with member markers
          for (const member of members) {
            member.color = this.memberColor(member.user_id)
          }
          familyLayer.loadMemberHistory(members)
        } else {
          familyLayer.clearHistory()
        }
      }

      // Update member info lines with sharing_since data
      this.updateInfoLines(members)
    } catch (error) {
      console.error("[Maps V2] Failed to load family history:", error)
    }
  }

  updateInfoLines(historyMembers) {
    if (!this.controller.hasFamilyMembersContainerTarget) return

    for (const member of historyMembers) {
      const infoEl = this.controller.familyMembersContainerTarget.querySelector(
        `[data-member-info="${member.user_id}"]`,
      )
      if (!infoEl || !member.sharing_since) continue

      const sharingDate = new Date(member.sharing_since)
      const daysSharing = Math.min(
        365,
        Math.floor(
          (Date.now() - sharingDate.getTime()) / (1000 * 60 * 60 * 24),
        ),
      )
      const formattedDate = sharingDate.toLocaleDateString(
        document.documentElement.lang || undefined,
        {
          month: "short",
          day: "numeric",
        },
      )

      infoEl.textContent = translate("family.sharing_since", {
        date: formattedDate,
        count: daysSharing,
      })
    }
  }

  renderMembersList(locations) {
    if (!this.controller.hasFamilyMembersContainerTarget) return

    const container = this.controller.familyMembersContainerTarget

    if (locations.length === 0) {
      container.innerHTML = `<p class="text-xs text-base-content/60">${translate("family.none_sharing")}</p>`
      return
    }

    container.replaceChildren(
      ...locations.map((location) => {
        const emailInitial =
          (location.name || location.email)?.charAt(0)?.toUpperCase() || "?"
        const color = this.memberColor(location.user_id)
        const timeZone = this.controller.timezoneValue || "UTC"
        const lastSeenDay = new Date(location.updated_at).toLocaleDateString(
          document.documentElement.lang || undefined,
          { timeZone, month: "short", day: "numeric" },
        )
        const lastSeen = `${lastSeenDay} ${formatTime(location.updated_at, { timeZone })}`

        const row = document.createElement("div")
        row.className =
          "flex items-center gap-2 p-2 hover:bg-base-200 rounded-lg cursor-pointer transition-colors"
        row.dataset.action = "click->maps--maplibre#centerOnFamilyMember"
        row.dataset.memberId = location.user_id

        const avatar = document.createElement("div")
        Object.assign(avatar.style, {
          backgroundColor: color,
          color: "white",
          borderRadius: "50%",
          width: "24px",
          height: "24px",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: "12px",
          fontWeight: "bold",
          flexShrink: "0",
        })
        avatar.textContent = emailInitial

        const info = document.createElement("div")
        info.className = "flex-1 min-w-0"

        const emailDiv = document.createElement("div")
        emailDiv.className = "text-sm font-medium truncate"
        emailDiv.textContent =
          location.name || location.email || translate("common.unknown")

        const timeDiv = document.createElement("div")
        timeDiv.className = "text-xs text-base-content/60"
        timeDiv.textContent = lastSeen

        const statusDiv = document.createElement("div")
        statusDiv.className = "text-xs text-info/70"
        statusDiv.dataset.memberInfo = location.user_id

        info.append(emailDiv)
        if (location.address) {
          const addressDiv = document.createElement("div")
          addressDiv.className = "text-xs text-base-content/70 truncate"
          addressDiv.title = location.address
          addressDiv.textContent = location.address
          info.append(addressDiv)
        }
        info.append(timeDiv, statusDiv)
        row.append(avatar, info)
        return row
      }),
    )
  }

  memberColor(userId) {
    const colors = [
      "#3b82f6",
      "#10b981",
      "#f59e0b",
      "#ef4444",
      "#8b5cf6",
      "#ec4899",
    ]
    // Use user ID to get consistent color
    const hash = userId
      .toString()
      .split("")
      .reduce((acc, char) => acc + char.charCodeAt(0), 0)
    return colors[hash % colors.length]
  }

  centerOnMember(event) {
    const memberId = event.currentTarget.dataset.memberId
    if (!memberId) return

    const familyLayer = this.controller.layerManager.getLayer("family")
    if (familyLayer) {
      familyLayer.centerOnMember(parseInt(memberId, 10))
      Toast.success(translate("messages.centered_on_family_member"))
    }
  }
}
