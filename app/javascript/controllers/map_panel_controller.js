import { Controller } from '@hotwired/stimulus'

/**
 * Map Panel Controller
 * Handles tab switching in the map control panel
 */
export default class extends Controller {
  static targets = ['tabButton', 'tabContent', 'title']

  // Tab title mappings
  static titles = {
    search: 'Search',
    layers: 'Map Layers',
    tools: 'Tools',
    links: 'Links',
    settings: 'Settings'
  }

  connect() {
    console.log('[Map Panel] Connected')
  }

  /**
   * Switch to a different tab
   */
  switchTab(event) {
    const button = event.currentTarget
    const tabName = button.dataset.tab

    this.activateTab(tabName)
  }

  /**
   * Programmatically switch to a tab by name
   */
  switchToTab(tabName) {
    this.activateTab(tabName)
  }

  /**
   * Internal method to activate a tab
   */
  activateTab(tabName) {
    // Find the button for this tab
    const button = this.tabButtonTargets.find(btn => btn.dataset.tab === tabName)

    // Update active button
    this.tabButtonTargets.forEach(btn => {
      btn.classList.remove('active')
    })
    if (button) {
      button.classList.add('active')
    }

    // Update tab content
    this.tabContentTargets.forEach(content => {
      const contentTab = content.dataset.tabContent
      if (contentTab === tabName) {
        content.classList.add('active')
      } else {
        content.classList.remove('active')
      }
    })

    // Update title
    this.titleTarget.textContent = this.constructor.titles[tabName] || tabName
  }
}
