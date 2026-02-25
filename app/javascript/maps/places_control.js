import L from "leaflet"
import { applyThemeToPanel } from "./theme_utils"

/**
 * Custom Leaflet control for managing Places layer visibility and filtering
 */
export function createPlacesControl(placesManager, tags, userTheme = "dark") {
  return L.Control.extend({
    options: {
      position: "topright",
    },

    onAdd: function (_map) {
      this.placesManager = placesManager
      this.tags = tags || []
      this.userTheme = userTheme
      this.activeFilters = new Set() // Track which tags are active
      this.showUntagged = false
      this.placesEnabled = false

      // Create main container
      const container = L.DomUtil.create(
        "div",
        "leaflet-bar leaflet-control leaflet-control-places",
      )

      // Prevent map interactions when clicking the control
      L.DomEvent.disableClickPropagation(container)
      L.DomEvent.disableScrollPropagation(container)

      // Create toggle button
      this.button = L.DomUtil.create(
        "a",
        "leaflet-control-places-button",
        container,
      )
      this.button.href = "#"
      this.button.title = "Places Layer"
      this.button.innerHTML = "📍"
      this.button.style.fontSize = "20px"
      this.button.style.width = "34px"
      this.button.style.height = "34px"
      this.button.style.lineHeight = "30px"
      this.button.style.textAlign = "center"
      this.button.style.textDecoration = "none"

      // Create panel (hidden by default)
      this.panel = L.DomUtil.create(
        "div",
        "leaflet-control-places-panel",
        container,
      )
      this.panel.style.display = "none"
      this.panel.style.marginTop = "5px"
      this.panel.style.minWidth = "200px"
      this.panel.style.maxWidth = "280px"
      this.panel.style.maxHeight = "400px"
      this.panel.style.overflowY = "auto"
      this.panel.style.padding = "10px"
      this.panel.style.borderRadius = "4px"
      this.panel.style.boxShadow = "0 2px 8px rgba(0,0,0,0.3)"

      // Apply theme to panel
      applyThemeToPanel(this.panel, this.userTheme)

      // Build panel content
      this.buildPanelContent()

      // Toggle panel on button click
      L.DomEvent.on(this.button, "click", (e) => {
        L.DomEvent.preventDefault(e)
        this.togglePanel()
      })

      return container
    },

    buildPanelContent: function () {
      const html = `
        <div style="margin-bottom: 10px; font-weight: bold; font-size: 14px; border-bottom: 1px solid rgba(128,128,128,0.3); padding-bottom: 8px;">
          📍 Places Layer
        </div>

        <!-- All Places Toggle -->
        <label style="display: flex; align-items: center; padding: 6px; cursor: pointer; border-radius: 4px; margin-bottom: 4px;"
               class="places-control-item"
               onmouseover="this.style.backgroundColor='rgba(128,128,128,0.2)'"
               onmouseout="this.style.backgroundColor='transparent'">
          <input type="checkbox"
                 data-filter="all"
                 style="margin-right: 8px; cursor: pointer;"
                 ${this.placesEnabled ? "checked" : ""}>
          <span style="font-weight: bold;">Show All Places</span>
        </label>

        <!-- Untagged Places Toggle -->
        <label style="display: flex; align-items: center; padding: 6px; cursor: pointer; border-radius: 4px; margin-bottom: 8px;"
               class="places-control-item"
               onmouseover="this.style.backgroundColor='rgba(128,128,128,0.2)'"
               onmouseout="this.style.backgroundColor='transparent'">
          <input type="checkbox"
                 data-filter="untagged"
                 style="margin-right: 8px; cursor: pointer;"
                 ${this.showUntagged ? "checked" : ""}>
          <span>Untagged Places</span>
        </label>

        ${
          this.tags.length > 0
            ? `
          <div style="border-top: 1px solid rgba(128,128,128,0.3); padding-top: 8px; margin-top: 8px;">
            <div style="font-size: 12px; font-weight: bold; margin-bottom: 6px; opacity: 0.7;">
              FILTER BY TAG
            </div>
            <div style="max-height: 250px; overflow-y: auto; margin-right: -5px; padding-right: 5px;">
              ${this.tags
                .map((tag) => {
                  const safeIcon = tag.icon ? this.escapeHtml(tag.icon) : "📍"
                  const safeColor = this.sanitizeColor(tag.color)
                  return `
                <label style="display: flex; align-items: center; padding: 6px; cursor: pointer; border-radius: 4px; margin-bottom: 2px;"
                       class="places-control-item"
                       onmouseover="this.style.backgroundColor='rgba(128,128,128,0.2)'"
                       onmouseout="this.style.backgroundColor='transparent'">
                  <input type="checkbox"
                         data-filter="tag"
                         data-tag-id="${tag.id}"
                         style="margin-right: 8px; cursor: pointer;"
                         ${this.activeFilters.has(tag.id) ? "checked" : ""}>
                  <span style="font-size: 18px; margin-right: 6px;">${safeIcon}</span>
                  <span style="flex: 1;">#${this.escapeHtml(tag.name)}</span>
                  ${tag.color ? `<span style="width: 12px; height: 12px; border-radius: 50%; background-color: ${safeColor}; margin-left: 4px;"></span>` : ""}
                </label>
              `
                })
                .join("")}
            </div>
          </div>
        `
            : '<div style="font-size: 12px; opacity: 0.6; padding: 8px; text-align: center;">No tags created yet</div>'
        }
      `

      this.panel.innerHTML = html

      // Add event listeners to checkboxes
      const checkboxes = this.panel.querySelectorAll('input[type="checkbox"]')
      checkboxes.forEach((cb) => {
        L.DomEvent.on(cb, "change", (e) => {
          this.handleFilterChange(e.target)
        })
      })
    },

    handleFilterChange: function (checkbox) {
      const filterType = checkbox.dataset.filter

      if (filterType === "all") {
        this.placesEnabled = checkbox.checked

        if (checkbox.checked) {
          // Show places layer
          this.placesManager.placesLayer.addTo(this.placesManager.map)
          this.applyCurrentFilters()
        } else {
          // Hide places layer
          this.placesManager.map.removeLayer(this.placesManager.placesLayer)
          // Uncheck all other filters
          this.activeFilters.clear()
          this.showUntagged = false
          this.buildPanelContent()
        }
      } else if (filterType === "untagged") {
        this.showUntagged = checkbox.checked
        this.applyCurrentFilters()
      } else if (filterType === "tag") {
        const tagId = parseInt(checkbox.dataset.tagId, 10)

        if (checkbox.checked) {
          this.activeFilters.add(tagId)
        } else {
          this.activeFilters.delete(tagId)
        }

        this.applyCurrentFilters()
      }

      // Update button appearance
      this.updateButtonState()
    },

    applyCurrentFilters: function () {
      if (!this.placesEnabled) return

      // Build filter criteria
      const tagIds = Array.from(this.activeFilters)

      if (this.showUntagged && tagIds.length === 0) {
        // Show only untagged places
        this.placesManager.filterByTags(null, true)
      } else if (tagIds.length > 0) {
        // Show places with specific tags
        this.placesManager.filterByTags(tagIds, false)
      } else {
        // Show all places (no filters)
        this.placesManager.filterByTags(null, false)
      }
    },

    updateButtonState: function () {
      if (this.placesEnabled) {
        this.button.style.backgroundColor = "#4CAF50"
        this.button.style.color = "white"
      } else {
        this.button.style.backgroundColor = ""
        this.button.style.color = ""
      }
    },

    togglePanel: function () {
      if (this.panel.style.display === "none") {
        this.panel.style.display = "block"
      } else {
        this.panel.style.display = "none"
      }
    },

    escapeHtml: (text) => {
      if (!text) return ""
      const div = document.createElement("div")
      div.textContent = text
      return div.innerHTML
    },

    sanitizeColor: (color) => {
      // Validate hex color format (#RGB or #RRGGBB)
      if (!color || typeof color !== "string") {
        return "#4CAF50" // Default green
      }

      const hexColorRegex = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/
      if (hexColorRegex.test(color)) {
        return color
      }

      return "#4CAF50" // Default green for invalid colors
    },
  })
}
