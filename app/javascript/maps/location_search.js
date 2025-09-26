// Location search functionality for the map
import { applyThemeToButton } from "./theme_utils";

class LocationSearch {
  constructor(map, apiKey, userTheme = 'dark') {
    this.map = map;
    this.apiKey = apiKey;
    this.userTheme = userTheme;
    this.searchResults = [];
    this.searchMarkersLayer = null;
    this.currentSearchQuery = '';
    this.searchTimeout = null;
    this.suggestionsVisible = false;
    this.currentSuggestionIndex = -1;

    // Make instance globally accessible for popup buttons
    window.locationSearchInstance = this;

    this.initializeSearchBar();
  }

  initializeSearchBar() {
    // Create search toggle button using Leaflet control (positioned below settings button)
    const SearchToggleControl = L.Control.extend({
      onAdd: function(map) {
        const button = L.DomUtil.create('button', 'location-search-toggle');
        button.innerHTML = '🔍';
        // Style the button with theme-aware styling
        applyThemeToButton(button, this.userTheme);
        button.style.width = '48px';
        button.style.height = '48px';
        button.style.borderRadius = '4px';
        button.style.padding = '0';
        button.style.fontSize = '18px';
        button.style.marginTop = '10px'; // Space below settings button
        button.title = 'Search locations';
        button.id = 'location-search-toggle';
        return button;
      }
    });

    // Add the search toggle control to the map
    this.map.addControl(new SearchToggleControl({ position: 'topleft' }));

    // Use setTimeout to ensure the DOM element is available
    setTimeout(() => {
      // Get reference to the created button
      const toggleButton = document.getElementById('location-search-toggle');

      if (toggleButton) {
        // Create inline search bar
        this.createInlineSearchBar();

        // Store references
        this.toggleButton = toggleButton;
        this.searchVisible = false;

        // Bind events
        this.bindSearchEvents();

        console.log('LocationSearch: Search button initialized successfully');
      } else {
        console.error('LocationSearch: Could not find search toggle button');
      }
    }, 100);
  }

  createInlineSearchBar() {
    // Create inline search bar that appears next to the search button
    const searchBar = document.createElement('div');
    searchBar.className = 'location-search-bar absolute bg-white border border-gray-300 rounded-lg shadow-lg hidden';
    searchBar.id = 'location-search-container'; // Use container ID for test compatibility
    searchBar.style.width = '400px'; // Increased width for better usability
    searchBar.style.maxHeight = '600px'; // Set max height for the entire search bar
    searchBar.style.padding = '12px'; // Increased padding
    searchBar.style.zIndex = '9999'; // Very high z-index to ensure visibility
    searchBar.style.overflow = 'visible'; // Allow content to overflow but results area will scroll

    searchBar.innerHTML = `
      <div class="flex items-center space-x-2">
        <input
          type="text"
          placeholder="Search locations..."
          class="flex-1 px-3 py-2 border border-gray-300 rounded focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent text-sm"
          id="location-search-input"
        />
        <button
          id="location-search-close"
          class="px-2 py-2 text-gray-400 hover:text-gray-600"
        >
          ✕
        </button>
      </div>

      <!-- Suggestions dropdown -->
      <div id="location-search-suggestions-panel" class="hidden mt-2 border-t border-gray-200">
        <div class="bg-gray-50 px-3 py-2 border-b text-xs font-medium text-gray-700">Suggestions</div>
        <div id="location-search-suggestions" class="max-h-48 overflow-y-auto border border-gray-200 rounded-b"></div>
      </div>

      <!-- Results dropdown -->
      <div id="location-search-results-panel" class="hidden mt-2 border-t border-gray-200">
        <div class="bg-gray-50 px-3 py-2 border-b text-xs font-medium text-gray-700">Results</div>
        <div id="location-search-results" class="border border-gray-200 rounded-b"></div>
      </div>
    `;

    // Add search bar to the map container
    this.map.getContainer().appendChild(searchBar);

    // Store references
    this.searchBar = searchBar;
    this.searchInput = document.getElementById('location-search-input');
    this.closeButton = document.getElementById('location-search-close');
    this.suggestionsContainer = document.getElementById('location-search-suggestions');
    this.suggestionsPanel = document.getElementById('location-search-suggestions-panel');
    this.resultsContainer = document.getElementById('location-search-results');
    this.resultsPanel = document.getElementById('location-search-results-panel');

    // Set scrolling properties immediately for results container with !important
    this.resultsContainer.style.setProperty('max-height', '400px', 'important');
    this.resultsContainer.style.setProperty('overflow-y', 'scroll', 'important');
    this.resultsContainer.style.setProperty('overflow-x', 'hidden', 'important');
    this.resultsContainer.style.setProperty('min-height', '0', 'important');
    this.resultsContainer.style.setProperty('display', 'block', 'important');

    // Set scrolling properties for suggestions container with !important
    this.suggestionsContainer.style.setProperty('max-height', '200px', 'important');
    this.suggestionsContainer.style.setProperty('overflow-y', 'scroll', 'important');
    this.suggestionsContainer.style.setProperty('overflow-x', 'hidden', 'important');
    this.suggestionsContainer.style.setProperty('min-height', '0', 'important');
    this.suggestionsContainer.style.setProperty('display', 'block', 'important');

    console.log('LocationSearch: Set scrolling properties on containers');

    // Prevent map scroll events when scrolling inside the search containers
    this.preventMapScrollOnContainers();

    // No clear button or default panel in inline mode
    this.clearButton = null;
    this.defaultPanel = null;
  }

  preventMapScrollOnContainers() {
    // Prevent scroll events from bubbling to the map when scrolling inside search containers
    const containers = [this.resultsContainer, this.suggestionsContainer, this.searchBar];

    containers.forEach(container => {
      if (container) {
        // Prevent wheel events (scroll) from reaching the map
        container.addEventListener('wheel', (e) => {
          e.stopPropagation();
        }, { passive: false });

        // Prevent touch scroll events from reaching the map
        container.addEventListener('touchstart', (e) => {
          e.stopPropagation();
        }, { passive: false });

        container.addEventListener('touchmove', (e) => {
          e.stopPropagation();
        }, { passive: false });

        container.addEventListener('touchend', (e) => {
          e.stopPropagation();
        }, { passive: false });

        // Also prevent mousewheel for older browsers
        container.addEventListener('mousewheel', (e) => {
          e.stopPropagation();
        }, { passive: false });

        // Prevent DOMMouseScroll for Firefox
        container.addEventListener('DOMMouseScroll', (e) => {
          e.stopPropagation();
        }, { passive: false });

        console.log('LocationSearch: Added scroll prevention to container', container.id || 'search-bar');
      }
    });
  }

  bindSearchEvents() {
    // Toggle search bar visibility
    this.toggleButton.addEventListener('click', (e) => {
      console.log('Search button clicked!');
      e.preventDefault();
      e.stopPropagation();
      this.showSearchBar();
    });

    // Close search bar
    this.closeButton.addEventListener('click', () => {
      this.hideSearchBar();
    });

    // Search on Enter key
    this.searchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        if (this.suggestionsVisible && this.currentSuggestionIndex >= 0) {
          this.selectSuggestion(this.currentSuggestionIndex);
        }
      }
    });

    // Clear search (no clear button in inline mode, handled by close button)

    // Handle real-time suggestions
    this.searchInput.addEventListener('input', (e) => {
      const query = e.target.value.trim();

      if (query.length > 0) {
        this.debouncedSuggestionSearch(query);
      } else {
        this.hideSuggestions();
        this.showDefaultState();
      }
    });

    // Handle keyboard navigation for suggestions
    this.searchInput.addEventListener('keydown', (e) => {
      if (this.suggestionsVisible) {
        switch (e.key) {
          case 'ArrowDown':
            e.preventDefault();
            this.navigateSuggestions(1);
            break;
          case 'ArrowUp':
            e.preventDefault();
            this.navigateSuggestions(-1);
            break;
          case 'Escape':
            this.hideSuggestions();
            this.showDefaultState();
            break;
        }
      }
    });

    // Close sidepanel on Escape key
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.searchVisible) {
        this.hideSearchBar();
      }
    });

    // Close search bar when clicking outside (but not on map interactions)
    document.addEventListener('click', (e) => {
      if (this.searchVisible &&
          !e.target.closest('#location-search-container') &&
          !e.target.closest('#location-search-toggle') &&
          !e.target.closest('.leaflet-container')) { // Don't close on map interactions
        this.hideSearchBar();
      }
    });

    // Maintain search bar position during map movements
    this.map.on('movestart zoomstart', () => {
      if (this.searchVisible) {
        // Store current button position before map movement
        this.storedButtonPosition = this.toggleButton.getBoundingClientRect();
      }
    });

    // Reposition search bar after map movements to maintain relative position
    this.map.on('moveend zoomend', () => {
      if (this.searchVisible && this.storedButtonPosition) {
        // Recalculate position based on new button position
        this.repositionSearchBar();
      }
    });
  }

  showLoading() {
    // Hide other panels and show results with loading
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-500"></div>
        <div class="text-sm text-gray-600 mt-3">Searching for "${this.escapeHtml(this.currentSearchQuery)}"...</div>
      </div>
    `;
  }

  showError(message) {
    // Hide other panels and show results with error
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="text-4xl mb-3">⚠️</div>
        <div class="text-sm font-medium text-red-600 mb-2">Search Failed</div>
        <div class="text-xs text-gray-500">${this.escapeHtml(message)}</div>
      </div>
    `;
  }

  displaySearchResults(data) {
    // Hide other panels and show results
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    if (!data.locations || data.locations.length === 0) {
      this.resultsContainer.innerHTML = `
        <div class="p-6 text-center text-gray-500">
          <div class="text-3xl mb-3">📍</div>
          <div class="text-sm font-medium">No visits found</div>
          <div class="text-xs mt-1">No visits found for "${this.escapeHtml(this.currentSearchQuery)}"</div>
        </div>
      `;
      return;
    }

    this.searchResults = data.locations;
    this.clearSearchMarkers();

    let resultsHtml = `
      <div class="p-4 border-b bg-gray-50">
        <div class="text-sm font-medium text-gray-700">Found ${data.total_locations} location(s)</div>
        <div class="text-xs text-gray-500 mt-1">for "${this.escapeHtml(this.currentSearchQuery)}"</div>
      </div>
    `;

    data.locations.forEach((location, index) => {
      resultsHtml += this.buildLocationResultHtml(location, index);
    });

    this.resultsContainer.innerHTML = resultsHtml;

    this.bindResultEvents();
  }

  buildLocationResultHtml(location, index) {
    const firstVisit = location.visits[location.visits.length - 1];
    const lastVisit = location.visits[0];

    // Group visits by year
    const visitsByYear = this.groupVisitsByYear(location.visits);

    return `
      <div class="location-result border-b" data-location-index="${index}">
        <div class="p-4">
          <div class="font-medium text-sm">${this.escapeHtml(location.place_name)}</div>
          <div class="text-xs text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
          <div class="flex justify-between items-center mt-3">
            <div class="text-xs text-blue-600">${location.total_visits} visit(s)</div>
            <div class="text-xs text-gray-500">
              first ${this.formatDateShort(firstVisit.date)}, last ${this.formatDateShort(lastVisit.date)}
            </div>
          </div>
        </div>

        <!-- Years Section -->
        <div class="border-t bg-gray-50">
          ${Object.entries(visitsByYear).map(([year, yearVisits]) => `
            <div class="year-section">
              <div class="year-toggle p-3 hover:bg-gray-100 cursor-pointer border-b border-gray-200 flex justify-between items-center"
                   data-location-index="${index}" data-year="${year}">
                <span class="text-sm font-medium text-gray-700">${year}</span>
                <span class="text-xs text-blue-600">${yearVisits.length} visits</span>
                <span class="year-arrow text-gray-400 transition-transform">▶</span>
              </div>
              <div class="year-visits hidden" id="year-${index}-${year}">
                ${yearVisits.map((visit) => `
                  <div class="visit-item text-xs text-gray-700 py-2 px-4 border-b border-gray-100 hover:bg-blue-50 cursor-pointer"
                       data-location-index="${index}" data-visit-index="${location.visits.indexOf(visit)}">
                    <div class="flex justify-between items-start">
                      <div>
                        📍 ${this.formatDateTime(visit.date)}
                      </div>
                      <div class="text-xs text-gray-500">
                        ${visit.duration_estimate}
                      </div>
                    </div>
                  </div>
                `).join('')}
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  }

  groupVisitsByYear(visits) {
    const groups = {};
    visits.forEach(visit => {
      const year = new Date(visit.date).getFullYear().toString();
      if (!groups[year]) {
        groups[year] = [];
      }
      groups[year].push(visit);
    });

    // Sort years descending (most recent first)
    const sortedGroups = {};
    Object.keys(groups)
      .sort((a, b) => parseInt(b) - parseInt(a))
      .forEach(year => {
        sortedGroups[year] = groups[year];
      });

    return sortedGroups;
  }

  formatDateShort(dateString) {
    const date = new Date(dateString);
    return date.toLocaleDateString('en-GB', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric'
    });
  }

  bindResultEvents() {
    // Bind click events to year toggles
    const yearToggles = this.resultsContainer.querySelectorAll('.year-toggle');
    yearToggles.forEach(toggle => {
      toggle.addEventListener('click', (e) => {
        e.stopPropagation();
        const locationIndex = parseInt(toggle.dataset.locationIndex);
        const year = toggle.dataset.year;
        this.toggleYear(locationIndex, year, toggle);
      });
    });

    // Bind click events to individual visits
    const visitResults = this.resultsContainer.querySelectorAll('.visit-item');
    visitResults.forEach(visit => {
      visit.addEventListener('click', (e) => {
        e.stopPropagation(); // Prevent triggering other clicks
        const locationIndex = parseInt(visit.dataset.locationIndex);
        const visitIndex = parseInt(visit.dataset.visitIndex);
        this.focusOnVisit(this.searchResults[locationIndex], visitIndex);
      });
    });
  }

  toggleYear(locationIndex, year, toggleElement) {
    const yearVisitsContainer = document.getElementById(`year-${locationIndex}-${year}`);
    const arrow = toggleElement.querySelector('.year-arrow');

    if (yearVisitsContainer.classList.contains('hidden')) {
      // Show visits
      yearVisitsContainer.classList.remove('hidden');
      arrow.style.transform = 'rotate(90deg)';
      arrow.textContent = '▼';
    } else {
      // Hide visits
      yearVisitsContainer.classList.add('hidden');
      arrow.style.transform = 'rotate(0deg)';
      arrow.textContent = '▶';
    }
  }


  focusOnLocation(location) {
    const [lat, lon] = location.coordinates;
    this.map.setView([lat, lon], 16);

    // Flash the marker
    const markers = this.searchMarkersLayer.getLayers();
    const targetMarker = markers.find(marker => {
      const latLng = marker.getLatLng();
      return Math.abs(latLng.lat - lat) < 0.0001 && Math.abs(latLng.lng - lon) < 0.0001;
    });

    if (targetMarker) {
      targetMarker.openPopup();
    }

    this.hideResults();
  }

  focusOnVisit(location, visitIndex) {
    const visit = location.visits[visitIndex];
    if (!visit) return;

    // Navigate to the visit coordinates (more precise than location coordinates)
    const [lat, lon] = visit.coordinates || location.coordinates;
    this.map.setView([lat, lon], 18); // Higher zoom for individual visit

    // Parse the visit timestamp to create a time filter
    const visitDate = new Date(visit.date);
    const startTime = new Date(visitDate.getTime() - (2 * 60 * 60 * 1000)); // 2 hours before
    const endTime = new Date(visitDate.getTime() + (2 * 60 * 60 * 1000));   // 2 hours after

    // Emit custom event for time filtering that other parts of the app can listen to
    const timeFilterEvent = new CustomEvent('locationSearch:timeFilter', {
      detail: {
        startTime: startTime.toISOString(),
        endTime: endTime.toISOString(),
        visitDate: visit.date,
        location: location.place_name,
        coordinates: [lat, lon]
      }
    });

    document.dispatchEvent(timeFilterEvent);

    // Create a special marker for the specific visit
    this.addVisitMarker(lat, lon, visit, location);

    // DON'T hide results - keep sidebar open
    // this.hideResults();
  }

  addVisitMarker(lat, lon, visit, location) {
    // Remove existing visit marker if any
    if (this.visitMarker) {
      this.map.removeLayer(this.visitMarker);
    }

    // Create a highlighted marker for the specific visit
    this.visitMarker = L.circleMarker([lat, lon], {
      radius: 12,
      fillColor: '#22c55e', // Green color to distinguish from search results
      color: '#ffffff',
      weight: 3,
      opacity: 1,
      fillOpacity: 0.9
    });

    const popupContent = `
      <div class="text-sm">
        <div class="font-semibold text-green-600">${this.escapeHtml(location.place_name)}</div>
        <div class="text-gray-600 mt-1">${this.escapeHtml(location.address || '')}</div>
        <div class="mt-2">
          <div class="text-xs text-gray-500">Visit Details:</div>
          <div class="text-sm">${this.formatDateTime(visit.date)}</div>
          <div class="text-xs text-gray-500">Duration: ${visit.duration_estimate}</div>
        </div>
        <div class="mt-3 pt-2 border-t border-gray-200 flex gap-2">
          <button onclick="window.locationSearchInstance?.createVisitAt?.(${lat}, ${lon}, '${this.escapeHtml(location.place_name)}', '${visit.date}', '${visit.duration_estimate}')"
                  class="text-xs bg-blue-600 text-white px-3 py-1 rounded hover:bg-blue-700 flex-1">
            Create Visit
          </button>
          <button onclick="this.getRootNode().host?.closePopup?.() || this.closest('.leaflet-popup').querySelector('.leaflet-popup-close-button')?.click()"
                  class="text-xs text-blue-600 hover:text-blue-800 px-2">
            Close
          </button>
        </div>
      </div>
    `;

    this.visitMarker.bindPopup(popupContent, {
      closeButton: true,
      autoClose: false, // Don't auto-close when clicking elsewhere
      closeOnEscapeKey: true, // Allow closing with Escape key
      closeOnClick: false // Don't close when clicking on map
    });

    this.visitMarker.addTo(this.map);
    this.visitMarker.openPopup();

    // Add event listener to clean up when popup is closed
    this.visitMarker.on('popupclose', () => {
      if (this.visitMarker) {
        this.map.removeLayer(this.visitMarker);
        this.visitMarker = null;
      }
    });

    // Store reference for manual cleanup if needed
    this.currentVisitMarker = this.visitMarker;
  }

  clearSearch() {
    this.searchInput.value = '';
    this.hideResults();
    this.clearSearchMarkers();
    this.clearVisitMarker();
    this.currentSearchQuery = '';
  }

  clearVisitMarker() {
    if (this.visitMarker) {
      this.map.removeLayer(this.visitMarker);
      this.visitMarker = null;
    }
    if (this.currentVisitMarker) {
      this.map.removeLayer(this.currentVisitMarker);
      this.currentVisitMarker = null;
    }

    // Remove any visit notifications
    const existingNotification = document.querySelector('.visit-navigation-notification');
    if (existingNotification) {
      existingNotification.remove();
    }
  }

  showSearchBar() {
    console.log('showSearchBar called');

    if (!this.searchBar) {
      console.error('Search bar element not found!');
      return;
    }

    // Position the search bar to the right of the search button at same height
    const buttonRect = this.toggleButton.getBoundingClientRect();
    const mapRect = this.map.getContainer().getBoundingClientRect();

    // Calculate position relative to the map container
    const left = buttonRect.right - mapRect.left + 15; // 15px gap to the right of button
    const top = buttonRect.top - mapRect.top; // Same height as button

    console.log('Positioning search bar at:', { left, top });

    // Position search bar next to the button
    this.searchBar.style.left = left + 'px';
    this.searchBar.style.top = top + 'px';
    this.searchBar.style.transform = 'none'; // Remove any transforms
    this.searchBar.style.position = 'absolute'; // Position relative to map container

    // Show the search bar
    this.searchBar.classList.remove('hidden');
    this.searchBar.style.setProperty('display', 'block', 'important');
    this.searchBar.style.visibility = 'visible';
    this.searchBar.style.opacity = '1';
    this.searchVisible = true;

    console.log('Search bar positioned next to button');

    // Focus the search input for immediate typing
    setTimeout(() => {
      if (this.searchInput) {
        this.searchInput.focus();
      }
    }, 100);
  }

  repositionSearchBar() {
    if (!this.searchBar || !this.searchVisible) return;

    // Get current button position after map movement
    const buttonRect = this.toggleButton.getBoundingClientRect();
    const mapRect = this.map.getContainer().getBoundingClientRect();

    // Calculate new position
    const left = buttonRect.right - mapRect.left + 15;
    const top = buttonRect.top - mapRect.top;

    // Update search bar position
    this.searchBar.style.left = left + 'px';
    this.searchBar.style.top = top + 'px';

    console.log('Search bar repositioned after map movement');
  }

  hideSearchBar() {
    this.searchBar.classList.add('hidden');
    this.searchBar.style.display = 'none';
    this.searchVisible = false;
    this.clearSearch();
    this.hideResults();
    this.hideSuggestions();
  }

  showDefaultState() {
    // No default panel in inline mode, just hide suggestions and results
    this.hideSuggestions();
    this.hideResults();
  }

  clearSearchMarkers() {
    // Note: No longer using search markers, but keeping method for compatibility
    // Only clear visit markers if they exist
    if (this.searchMarkersLayer) {
      this.map.removeLayer(this.searchMarkersLayer);
      this.searchMarkersLayer = null;
    }
  }

  hideResults() {
    if (this.resultsPanel) {
      this.resultsPanel.classList.add('hidden');
    }
  }

  // Suggestion-related methods
  debouncedSuggestionSearch(query) {
    // Clear existing timeout
    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
    }

    // Set new timeout for debounced search
    this.searchTimeout = setTimeout(() => {
      this.performSuggestionSearch(query);
    }, 300); // 300ms debounce delay
  }

  async performSuggestionSearch(query) {
    if (query.length < 2) {
      this.hideSuggestions();
      return;
    }

    // Show loading state for suggestions
    this.showSuggestionsLoading();

    try {
      const response = await fetch(`/api/v1/locations/suggestions?q=${encodeURIComponent(query)}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Suggestions failed: ${response.status}`);
      }

      const data = await response.json();
      this.displaySuggestions(data.suggestions || []);

    } catch (error) {
      console.error('Suggestion search error:', error);
      this.hideSuggestions();
    }
  }

  showSuggestionsLoading() {
    // Hide other panels and show suggestions with loading
    this.resultsPanel.classList.add('hidden');
    this.suggestionsPanel.classList.remove('hidden');

    this.suggestionsContainer.innerHTML = `
      <div class="p-6 text-center">
        <div class="text-2xl animate-bounce">⏳</div>
        <div class="text-sm text-gray-500 mt-2">Finding suggestions...</div>
      </div>
    `;
  }

  displaySuggestions(suggestions) {
    if (!suggestions.length) {
      this.hideSuggestions();
      return;
    }

    // Hide other panels and show suggestions
    this.resultsPanel.classList.add('hidden');
    this.suggestionsPanel.classList.remove('hidden');

    // Build suggestions HTML
    let suggestionsHtml = '';
    suggestions.forEach((suggestion, index) => {
      const isActive = index === this.currentSuggestionIndex;
      suggestionsHtml += `
        <div class="suggestion-item p-4 border-b border-gray-100 hover:bg-blue-50 cursor-pointer ${isActive ? 'bg-blue-50 text-blue-700' : ''}"
             data-suggestion-index="${index}">
          <div class="font-medium text-sm">${this.escapeHtml(suggestion.name)}</div>
          <div class="text-xs text-gray-500 mt-1">${this.escapeHtml(suggestion.address || '')}</div>
        </div>
      `;
    });

    this.suggestionsContainer.innerHTML = suggestionsHtml;
    this.suggestionsVisible = true;
    this.suggestions = suggestions;

    // Bind click events to suggestions
    this.bindSuggestionEvents();
  }

  bindSuggestionEvents() {
    const suggestionItems = this.suggestionsContainer.querySelectorAll('.suggestion-item');
    suggestionItems.forEach(item => {
      item.addEventListener('click', (e) => {
        const index = parseInt(e.currentTarget.dataset.suggestionIndex);
        this.selectSuggestion(index);
      });
    });
  }

  navigateSuggestions(direction) {
    if (!this.suggestions || !this.suggestions.length) return;

    const maxIndex = this.suggestions.length - 1;

    if (direction > 0) {
      // Arrow down
      this.currentSuggestionIndex = this.currentSuggestionIndex < maxIndex
        ? this.currentSuggestionIndex + 1
        : 0;
    } else {
      // Arrow up
      this.currentSuggestionIndex = this.currentSuggestionIndex > 0
        ? this.currentSuggestionIndex - 1
        : maxIndex;
    }

    this.highlightActiveSuggestion();
  }

  highlightActiveSuggestion() {
    const suggestionItems = this.suggestionsContainer.querySelectorAll('.suggestion-item');

    suggestionItems.forEach((item, index) => {
      if (index === this.currentSuggestionIndex) {
        item.classList.add('bg-blue-50', 'text-blue-700');
        item.classList.remove('bg-gray-50');
      } else {
        item.classList.remove('bg-blue-50', 'text-blue-700');
        item.classList.add('bg-gray-50');
      }
    });
  }

  selectSuggestion(index) {
    if (!this.suggestions || index < 0 || index >= this.suggestions.length) return;

    const suggestion = this.suggestions[index];
    this.searchInput.value = suggestion.name;
    this.hideSuggestions();
    this.showSearchLoading(suggestion.name);
    this.performCoordinateSearch(suggestion); // Use coordinate-based search for selected suggestion
  }

  showSearchLoading(locationName) {
    // Hide other panels and show loading for search results
    this.suggestionsPanel.classList.add('hidden');
    this.resultsPanel.classList.remove('hidden');

    this.resultsContainer.innerHTML = `
      <div class="p-8 text-center">
        <div class="text-3xl animate-bounce">⏳</div>
        <div class="text-sm text-gray-600 mt-3">Searching visits to</div>
        <div class="text-sm font-medium text-gray-800">${this.escapeHtml(locationName)}</div>
      </div>
    `;
  }

  async performCoordinateSearch(suggestion) {
    this.currentSearchQuery = suggestion.name;
    // Loading state already shown by showSearchLoading

    try {
      const params = new URLSearchParams({
        lat: suggestion.coordinates[0],
        lon: suggestion.coordinates[1],
        name: suggestion.name,
        address: suggestion.address || ''
      });

      const response = await fetch(`/api/v1/locations?${params}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json'
        }
      });

      if (!response.ok) {
        throw new Error(`Coordinate search failed: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      this.displaySearchResults(data);

    } catch (error) {
      console.error('Coordinate search error:', error);
      this.showError('Failed to search locations. Please try again.');
    }
  }

  hideSuggestions() {
    this.suggestionsPanel.classList.add('hidden');
    this.suggestionsVisible = false;
    this.currentSuggestionIndex = -1;
    this.suggestions = [];

    if (this.searchTimeout) {
      clearTimeout(this.searchTimeout);
      this.searchTimeout = null;
    }
  }

  createVisitAt(lat, lon, placeName, visitDate, durationEstimate) {
    console.log(`Creating visit at ${lat}, ${lon} for ${placeName} at ${visitDate} (duration: ${durationEstimate})`);

    // Close the current visit popup
    if (this.visitMarker) {
      this.visitMarker.closePopup();
    }

    // Calculate start and end times from the original visit
    const { startTime, endTime } = this.calculateVisitTimes(visitDate, durationEstimate);

    this.showBasicVisitForm(lat, lon, placeName, startTime, endTime);
  }

  showBasicVisitForm(lat, lon, placeName, presetStartTime, presetEndTime) {
    // Close any existing visit form popups first
    const existingPopups = document.querySelectorAll('.basic-visit-form-popup');
    existingPopups.forEach(popup => {
      const leafletPopup = popup.closest('.leaflet-popup');
      if (leafletPopup) {
        const closeButton = leafletPopup.querySelector('.leaflet-popup-close-button');
        if (closeButton) closeButton.click();
      }
    });

    // Use preset times if available, otherwise use current time defaults
    let startTime, endTime;

    if (presetStartTime && presetEndTime) {
      startTime = presetStartTime;
      endTime = presetEndTime;
      console.log('Using preset times:', { startTime, endTime });
    } else {
      console.log('No preset times provided, using defaults');
      // Get current date/time for default values
      const now = new Date();
      const oneHourLater = new Date(now.getTime() + (60 * 60 * 1000));

      // Format dates for datetime-local input
      const formatDateTime = (date) => {
        return date.toISOString().slice(0, 16);
      };

      startTime = formatDateTime(now);
      endTime = formatDateTime(oneHourLater);
    }

    // Create form HTML
    const formHTML = `
      <div class="visit-form" style="min-width: 280px;">
        <h3 style="margin-top: 0; margin-bottom: 15px; font-size: 16px; color: #333;">Add New Visit</h3>

        <form id="basic-add-visit-form" style="display: flex; flex-direction: column; gap: 10px;">
          <div>
            <label for="basic-visit-name" style="display: block; margin-bottom: 5px; font-weight: bold; font-size: 14px;">Name:</label>
            <input type="text" id="basic-visit-name" name="name" required value="${this.escapeHtml(placeName)}"
                   style="width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;"
                   placeholder="Enter visit name">
          </div>

          <div>
            <label for="basic-visit-start" style="display: block; margin-bottom: 5px; font-weight: bold; font-size: 14px;">Start Time:</label>
            <input type="datetime-local" id="basic-visit-start" name="started_at" required value="${startTime}"
                   style="width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;">
          </div>

          <div>
            <label for="basic-visit-end" style="display: block; margin-bottom: 5px; font-weight: bold; font-size: 14px;">End Time:</label>
            <input type="datetime-local" id="basic-visit-end" name="ended_at" required value="${endTime}"
                   style="width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 14px;">
          </div>

          <input type="hidden" name="latitude" value="${lat}">
          <input type="hidden" name="longitude" value="${lon}">

          <div style="display: flex; gap: 10px; margin-top: 15px;">
            <button type="submit" style="flex: 1; background: #28a745; color: white; border: none; padding: 10px; border-radius: 4px; cursor: pointer; font-weight: bold;">
              Create Visit
            </button>
            <button type="button" id="basic-cancel-visit" style="flex: 1; background: #dc3545; color: white; border: none; padding: 10px; border-radius: 4px; cursor: pointer; font-weight: bold;">
              Cancel
            </button>
          </div>
        </form>
      </div>
    `;

    // Create popup at the location
    const basicVisitPopup = L.popup({
      closeOnClick: false,
      autoClose: false,
      maxWidth: 300,
      className: 'basic-visit-form-popup'
    })
      .setLatLng([lat, lon])
      .setContent(formHTML)
      .openOn(this.map);

    // Add event listeners after the popup is added to DOM
    setTimeout(() => {
      const form = document.getElementById('basic-add-visit-form');
      const cancelButton = document.getElementById('basic-cancel-visit');
      const nameInput = document.getElementById('basic-visit-name');

      if (form) {
        form.addEventListener('submit', (e) => this.handleBasicFormSubmit(e, basicVisitPopup));
      }

      if (cancelButton) {
        cancelButton.addEventListener('click', () => {
          this.map.closePopup(basicVisitPopup);
        });
      }

      // Focus and select the name input
      if (nameInput) {
        nameInput.focus();
        nameInput.select();
      }
    }, 100);
  }

  async handleBasicFormSubmit(event, popup) {
    event.preventDefault();

    const form = event.target;
    const formData = new FormData(form);

    // Get form values
    const visitData = {
      visit: {
        name: formData.get('name'),
        started_at: formData.get('started_at'),
        ended_at: formData.get('ended_at'),
        latitude: formData.get('latitude'),
        longitude: formData.get('longitude')
      }
    };

    // Validate that end time is after start time
    const startTime = new Date(visitData.visit.started_at);
    const endTime = new Date(visitData.visit.ended_at);

    if (endTime <= startTime) {
      alert('End time must be after start time');
      return;
    }

    // Disable form while submitting
    const submitButton = form.querySelector('button[type="submit"]');
    const originalText = submitButton.textContent;
    submitButton.disabled = true;
    submitButton.textContent = 'Creating...';

    try {
      const response = await fetch(`/api/v1/visits`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': `Bearer ${this.apiKey}`
        },
        body: JSON.stringify(visitData)
      });

      const data = await response.json();

      if (response.ok) {
        alert(`Visit "${visitData.visit.name}" created successfully!`);
        this.map.closePopup(popup);

        // Try to refresh visits layer if available
        this.refreshVisitsIfAvailable();
      } else {
        const errorMessage = data.error || data.message || 'Failed to create visit';
        alert(errorMessage);
      }
    } catch (error) {
      console.error('Error creating visit:', error);
      alert('Network error: Failed to create visit');
    } finally {
      // Re-enable form
      submitButton.disabled = false;
      submitButton.textContent = originalText;
    }
  }

  refreshVisitsIfAvailable() {
    // Try to refresh visits layer if available
    const mapsController = document.querySelector('[data-controller*="maps"]');
    if (mapsController) {
      const stimulusApp = window.Stimulus || window.stimulus;
      if (stimulusApp) {
        const controller = stimulusApp.getControllerForElementAndIdentifier(mapsController, 'maps');
        if (controller && controller.visitsManager && controller.visitsManager.fetchAndDisplayVisits) {
          console.log('Refreshing visits layer after creating visit');
          controller.visitsManager.fetchAndDisplayVisits();
        }
      }
    }
  }

  calculateVisitTimes(visitDate, durationEstimate) {
    if (!visitDate) {
      return { startTime: null, endTime: null };
    }

    try {
      // Parse the visit date (e.g., "2022-12-27T18:01:00.000Z")
      const visitDateTime = new Date(visitDate);

      // Parse duration estimate (e.g., "~15m", "~1h 44m", "~2h 30m")
      let durationMinutes = 15; // Default to 15 minutes if parsing fails

      if (durationEstimate) {
        const durationStr = durationEstimate.replace('~', '').trim();

        // Match patterns like "15m", "1h 44m", "2h", etc.
        const hoursMatch = durationStr.match(/(\d+)h/);
        const minutesMatch = durationStr.match(/(\d+)m/);

        let hours = 0;
        let minutes = 0;

        if (hoursMatch) {
          hours = parseInt(hoursMatch[1]);
        }
        if (minutesMatch) {
          minutes = parseInt(minutesMatch[1]);
        }

        durationMinutes = (hours * 60) + minutes;

        // If no matches found, try to parse as pure minutes
        if (durationMinutes === 0) {
          const pureMinutes = parseInt(durationStr);
          if (!isNaN(pureMinutes)) {
            durationMinutes = pureMinutes;
          }
        }
      }

      // Calculate start time (visit time) and end time (visit time + duration)
      const startTime = visitDateTime.toISOString().slice(0, 16); // Format for datetime-local
      const endDateTime = new Date(visitDateTime.getTime() + (durationMinutes * 60 * 1000));
      const endTime = endDateTime.toISOString().slice(0, 16);

      console.log(`Calculated visit times: ${startTime} to ${endTime} (duration: ${durationMinutes} minutes)`);

      return { startTime, endTime };
    } catch (error) {
      console.error('Error calculating visit times:', error);
      return { startTime: null, endTime: null };
    }
  }

  // Utility methods
  escapeHtml(text) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return text ? text.replace(/[&<>"']/g, m => map[m]) : '';
  }

  formatDate(dateString) {
    return new Date(dateString).toLocaleDateString();
  }

  formatDateTime(dateString) {
    return new Date(dateString).toLocaleDateString() + ' ' +
           new Date(dateString).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'});
  }

  updateTheme(newTheme) {
    this.userTheme = newTheme;

    // Update search button theme if it exists
    const searchButton = document.getElementById('location-search-toggle');
    if (searchButton) {
      applyThemeToButton(searchButton, newTheme);
    }
  }
}

export { LocationSearch };
