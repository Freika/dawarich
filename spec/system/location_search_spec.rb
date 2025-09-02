# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Location Search Feature', type: :system, js: true do
  let(:user) { create(:user) }

  before do
    driven_by(:selenium_chrome_headless)
    # Alternative for debugging: driven_by(:rack_test)
    login_as user, scope: :user
    
    # Create some test points near Berlin with proper PostGIS point format
    create(:point, 
      user: user, 
      latitude: 52.5200, 
      longitude: 13.4050,
      timestamp: 1.day.ago.to_i,
      city: 'Berlin',
      country: 'Germany'
    )
    
    create(:point,
      user: user,
      latitude: 52.5201,
      longitude: 13.4051,
      timestamp: 2.hours.ago.to_i,
      city: 'Berlin',
      country: 'Germany'
    )
    
    # Ensure points are properly saved and accessible
    expect(user.points.count).to eq(2)

    # Mock the geocoding service to avoid external API calls
    allow_any_instance_of(LocationSearch::GeocodingService).to receive(:search) do |_service, query|
      case query.downcase
      when /kaufland/
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Kaufland Mitte',
            address: 'Alexanderplatz 1, Berlin',
            type: 'shop'
          }
        ]
      when /nonexistent/
        []
      else
        [
          {
            lat: 52.5200,
            lon: 13.4050,
            name: 'Generic Location',
            address: 'Berlin, Germany',
            type: 'unknown'
          }
        ]
      end
    end
  end

  describe 'Search Bar' do
    before do
      visit '/map'
      
      # Debug: check what's actually on the page
      puts "Page title: #{page.title}"
      puts "Page body contains 'Map': #{page.has_content?('Map')}"
      puts "Page has #map element: #{page.has_css?('#map')}"
      puts "Page HTML preview: #{page.html[0..500]}..."
      
      # Check if map container exists
      if page.has_css?('#map')
        puts "Map element found!"
      else
        puts "Map element NOT found - checking for any div elements:"
        puts "Number of div elements: #{page.all('div').count}"
      end
      
      sleep(3) # Give time for JavaScript to initialize
    end

    it 'displays search toggle button on the map' do
      expect(page).to have_css('#location-search-toggle')
      expect(page).to have_css('button:contains("🔍")')
    end

    it 'initially hides the search bar' do
      expect(page).to have_css('#location-search-container.hidden')
    end

    it 'shows search bar when toggle button is clicked' do
      find('#location-search-toggle').click
      
      expect(page).to have_css('#location-search-container:not(.hidden)')
      expect(page).to have_css('#location-search-input')
    end

    it 'hides search bar when toggle button is clicked again' do
      # Show search bar first
      find('#location-search-toggle').click
      expect(page).to have_css('#location-search-container:not(.hidden)')
      
      # Hide it
      find('#location-search-toggle').click
      expect(page).to have_css('#location-search-container.hidden')
    end

    it 'shows placeholder text in search input when visible' do
      find('#location-search-toggle').click
      
      search_input = find('#location-search-input')
      expect(search_input[:placeholder]).to include('Search locations')
    end

    context 'when performing a search' do
      before do
        # Show the search bar first
        find('#location-search-toggle').click
      end

      it 'shows loading state during search' do
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end

        # Should show loading indicator briefly
        expect(page).to have_content('Searching for "Kaufland"')
      end

      it 'displays search results for existing locations' do
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end

        # Wait for results to appear
        within('#location-search-results') do
          expect(page).to have_content('Kaufland Mitte')
          expect(page).to have_content('Alexanderplatz 1, Berlin')
          expect(page).to have_content('visit(s)')
        end
      end

      it 'shows visit details in results' do
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end

        within('#location-search-results') do
          # Should show visit timestamps and distances
          expect(page).to have_css('.location-result')
          expect(page).to have_content('m away') # distance indicator
        end
      end

      it 'handles search with Enter key' do
        fill_in 'location-search-input', with: 'Kaufland'
        find('#location-search-input').send_keys(:enter)

        within('#location-search-results') do
          expect(page).to have_content('Kaufland Mitte')
        end
      end

      it 'displays appropriate message for no results' do
        fill_in 'location-search-input', with: 'NonexistentPlace'
        click_button '🔍'

        within('#location-search-results') do
          expect(page).to have_content('No visits found for "NonexistentPlace"')
        end
      end
    end

    context 'with search interaction' do
      before do
        # Show the search bar first
        find('#location-search-toggle').click
      end

      it 'focuses search input when search bar is shown' do
        expect(page).to have_css('#location-search-input:focus')
      end

      it 'closes search bar when Escape key is pressed' do
        find('#location-search-input').send_keys(:escape)
        
        expect(page).to have_css('#location-search-container.hidden')
      end

      it 'shows clear button when text is entered' do
        search_input = find('#location-search-input')
        clear_button = find('#location-search-clear')
        
        expect(clear_button).not_to be_visible
        
        search_input.fill_in(with: 'test')
        expect(clear_button).to be_visible
      end

      it 'clears search when clear button is clicked' do
        search_input = find('#location-search-input')
        clear_button = find('#location-search-clear')
        
        search_input.fill_in(with: 'test search')
        clear_button.click
        
        expect(search_input.value).to be_empty
        expect(clear_button).not_to be_visible
      end

      it 'hides results and search bar when clicking outside' do
        # First, show search bar and perform search
        find('#location-search-toggle').click
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end
        
        # Wait for results to show
        expect(page).to have_css('#location-search-results:not(.hidden)')
        
        # Click outside the search area (left side of map to avoid controls)
        page.execute_script("document.querySelector('#map').dispatchEvent(new MouseEvent('click', {clientX: 100, clientY: 200}))")
        
        # Both results and search bar should be hidden
        expect(page).to have_css('#location-search-results.hidden')
        expect(page).to have_css('#location-search-container.hidden')
      end
    end

    context 'with map interaction' do
      before do
        # Show the search bar first
        find('#location-search-toggle').click
      end

      it 'completes search and shows results without location markers' do
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end

        # Wait for search to complete
        expect(page).to have_content('Kaufland Mitte')

        # Verify search results are displayed (no location markers are added to keep map clean)
        expect(page).to have_content('Found 1 location(s)')
      end

      it 'focuses map on clicked search result' do
        fill_in 'location-search-input', with: 'Kaufland'
        within('#location-search-container') do
          click_button '🔍'
        end

        within('#location-search-results') do
          find('.location-result').click
        end

        # Results should be hidden after clicking
        expect(page).to have_css('#location-search-results.hidden')
      end
    end

    context 'with error handling' do
      before do
        # Mock API to return error
        allow_any_instance_of(LocationSearch::PointFinder).to receive(:call).and_raise(StandardError.new('API Error'))
      end

      it 'handles API errors gracefully' do
        fill_in 'location-search-input', with: 'test'
        click_button '🔍'

        within('#location-search-results') do
          expect(page).to have_content('Failed to search locations')
        end
      end
    end

    context 'with authentication' do
      it 'includes API key in search requests' do
        # This test verifies that the search component receives the API key
        # from the data attribute and includes it in requests
        
        map_element = find('#map')
        expect(map_element['data-api_key']).to eq(user.api_key)
      end
    end
  end

  describe 'Search API Integration' do
    it 'makes authenticated requests to the search API' do
      # Test that the frontend makes proper API calls
      visit '/map'
      
      fill_in 'location-search-input', with: 'Kaufland'
      
      # Intercept the API request
      expect(page.driver.browser.manage).to receive(:add_cookie).with(
        hash_including(name: 'api_request_made')
      )
      
      click_button '🔍'
    end
  end

  describe 'Real-world Search Scenarios' do
    context 'with business name search' do
      it 'finds visits to business locations' do
        visit '/map'
        
        fill_in 'location-search-input', with: 'Kaufland'
        click_button '🔍'
        
        expect(page).to have_content('Kaufland Mitte')
        expect(page).to have_content('visit(s)')
      end
    end

    context 'with address search' do
      it 'handles street address searches' do
        visit '/map'
        
        fill_in 'location-search-input', with: 'Alexanderplatz 1'
        click_button '🔍'
        
        within('#location-search-results') do
          expect(page).to have_content('location(s)')
        end
      end
    end

    context 'with multiple search terms' do
      it 'handles complex search queries' do
        visit '/map'
        
        fill_in 'location-search-input', with: 'Kaufland Berlin'
        click_button '🔍'
        
        # Should handle multi-word searches
        expect(page).to have_content('location(s) for "Kaufland Berlin"')
      end
    end

    context 'with real-time suggestions' do
      before do
        # Mock the geocoding service to return suggestions
        allow_any_instance_of(LocationSearch::GeocodingService).to receive(:search) do |_service, query|
          case query.downcase
          when /kau/
            [
              {
                lat: 52.5200,
                lon: 13.4050,
                name: 'Kaufland Mitte',
                address: 'Alexanderplatz 1, Berlin',
                type: 'shop'
              },
              {
                lat: 52.5100,
                lon: 13.4000,
                name: 'Kaufland Friedrichshain',
                address: 'Warschauer Str. 80, Berlin',
                type: 'shop'
              }
            ]
          else
            []
          end
        end

        # Show the search bar first
        find('#location-search-toggle').click
      end

      it 'shows suggestions as user types' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'Kau')

        # Wait for debounced search to trigger
        sleep(0.4)

        within('#location-search-suggestions') do
          expect(page).to have_content('Kaufland Mitte')
          expect(page).to have_content('Alexanderplatz 1, Berlin')
          expect(page).to have_content('Kaufland Friedrichshain')
        end
      end

      it 'allows selecting suggestions with mouse click' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'Kau')
        sleep(0.4)

        within('#location-search-suggestions') do
          find('.suggestion-item', text: 'Kaufland Mitte').click
        end

        expect(search_input.value).to eq('Kaufland Mitte')
        expect(page).to have_css('#location-search-suggestions.hidden')
      end

      it 'allows keyboard navigation through suggestions' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'Kau')
        sleep(0.4)

        # Navigate down through suggestions
        search_input.send_keys(:arrow_down)
        within('#location-search-suggestions') do
          expect(page).to have_css('.suggestion-item.bg-blue-50', text: 'Kaufland Mitte')
        end

        search_input.send_keys(:arrow_down)
        within('#location-search-suggestions') do
          expect(page).to have_css('.suggestion-item.bg-blue-50', text: 'Kaufland Friedrichshain')
        end

        # Select with Enter
        search_input.send_keys(:enter)
        expect(search_input.value).to eq('Kaufland Friedrichshain')
      end

      it 'hides suggestions when input is cleared' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'Kau')
        sleep(0.4)

        expect(page).to have_css('#location-search-suggestions:not(.hidden)')

        search_input.set('')
        expect(page).to have_css('#location-search-suggestions.hidden')
      end

      it 'hides suggestions on Escape key' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'Kau')
        sleep(0.4)

        expect(page).to have_css('#location-search-suggestions:not(.hidden)')

        search_input.send_keys(:escape)
        expect(page).to have_css('#location-search-suggestions.hidden')
      end

      it 'does not show suggestions for queries shorter than 2 characters' do
        search_input = find('#location-search-input')
        search_input.fill_in(with: 'K')
        sleep(0.4)

        expect(page).to have_css('#location-search-suggestions.hidden')
      end
    end
  end

  private

  def sign_in(user)
    visit '/users/sign_in'
    # Try different selectors for email field
    if page.has_field?('Email')
      fill_in 'Email', with: user.email
    elsif page.has_field?('user_email')
      fill_in 'user_email', with: user.email
    elsif page.has_css('input[type="email"]')
      find('input[type="email"]').fill_in with: user.email
    else
      raise "Could not find email field"
    end
    
    # Try different selectors for password field  
    if page.has_field?('Password')
      fill_in 'Password', with: user.password
    elsif page.has_field?('user_password')
      fill_in 'user_password', with: user.password
    elsif page.has_css('input[type="password"]')
      find('input[type="password"]').fill_in with: user.password
    else
      raise "Could not find password field"
    end
    
    click_button 'Log in'
  end
end