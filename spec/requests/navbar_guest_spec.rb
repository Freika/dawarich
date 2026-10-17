# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Navbar app menu', type: :request do
  def menu_hrefs
    Nokogiri::HTML(response.body).css('.navbar a').map { _1['href'] }
  end

  def mobile_menu_toggle
    Nokogiri::HTML(response.body).at_css('[aria-controls="mobile-navigation-menu"]')
  end

  it 'is hidden from a visitor who has not signed in' do
    get new_user_session_path

    expect(menu_hrefs).not_to include(trips_url, insights_url, points_url)
    expect(mobile_menu_toggle).to be_nil
  end

  it 'is shown to a signed-in user' do
    sign_in create(:user)

    get trips_path

    expect(menu_hrefs).to include(trips_url, insights_url, points_url)
    expect(mobile_menu_toggle).to be_present
  end
end
