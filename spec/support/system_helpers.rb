# frozen_string_literal: true

module SystemHelpers
  def sign_in_user(user, password = 'password123')
    visit new_user_session_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: password
    click_button 'Log in'
  end

  def sign_in_and_visit_map(user, password = 'password123')
    sign_in_user(user, password)
    expect(page).to have_current_path(map_path)
    expect(page).to have_css('.leaflet-container', wait: 10)
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end
