# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale switch link', type: :request do
  def switch_link_href(body)
    Nokogiri::HTML(body).at_css('a[hreflang]')&.[]('href')
  end

  it 'keeps the link on this host when the query string carries a host' do
    get root_path, params: { host: 'evil.example.com' }

    expect(response).to have_http_status(:ok)

    href = switch_link_href(response.body)
    expect(href).to start_with('/')
    expect(href).not_to start_with('//')
    expect(href).not_to include('://')
  end

  it 'renders when the query string carries routing keys' do
    get root_path, params: { controller: 'nope', action: 'nope' }

    expect(response).to have_http_status(:ok)
    expect(switch_link_href(response.body)).to start_with('/?')
  end

  it 'preserves unrelated query parameters' do
    get root_path, params: { utm_source: 'newsletter' }

    expect(switch_link_href(response.body)).to eq('/?locale=de&utm_source=newsletter')
  end

  it 'points at a reachable path when a form re-renders after a validation error' do
    user = create(:user, password: 'password123456')
    sign_in user

    patch user_registration_path,
          params: { user: { email: '', current_password: 'password123456' } }

    expect(response).to have_http_status(:unprocessable_content)

    href = switch_link_href(response.body)
    expect(href).to be_present
    expect(Rails.application.routes.recognize_path(href.split('?').first, method: :get)).to be_present
  end
end
