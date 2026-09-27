# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the application layout as Rails renders it', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/layout') }
  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }
  let(:header_names) do
    %w[x-frame-options x-xss-protection x-content-type-options x-permitted-cross-domain-policies referrer-policy]
  end

  def capture(name, path, state, headers = {})
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    content = doc.at_css('body > div.container > div.w-full > div.flex')
    raise "#{path} does not render layouts/application" unless content

    content.children.remove
    scrub!(doc)
    assert_safe!(doc)
    File.write(dir.join("#{name}.html"), doc.at_css('body').to_html)
    File.write(dir.join("#{name}.head.html"), doc.at_css('head').to_html)
    meta = {
      state: state,
      html: doc.at_css('html').attributes.transform_values(&:value),
      headers: header_names.index_with { |header| response.headers[header] }
    }
    File.write(dir.join("#{name}.json"), "#{JSON.pretty_generate(meta)}\n")
  end

  def scrub!(doc)
    doc.css('[signed-stream-name]').each { |node| node['signed-stream-name'] = 'SIGNED' }
    doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }

    doc.css('a[href]').each do |node|
      uri = URI.parse(node['href'])
      next unless uri.path == '/auth/dawarich'

      node['href'] = node['href'].sub(/([?&]token=)[^&]+/, '\\1REDACTED')
    rescue URI::InvalidURIError
      next
    end
  end

  def assert_safe!(doc)
    html = doc.to_html
    raise 'fixture contains a JWT-shaped value' if html.match?(/eyJ[A-Za-z0-9_-]+\./)
    raise 'fixture contains an unsigned stream name' if html.match?(/signed-stream-name="(?!SIGNED")/)
  end

  def user_state(user)
    { id: user.id, email: user.email, theme: user.theme, settings: user.settings, admin: user.admin,
      status: user.status, plan: user.plan, active_until: user.active_until&.utc&.iso8601(6) }
  end

  before { FileUtils.mkdir_p(dir) }

  it 'rejects a fixture containing a JWT-shaped value and unsigned stream name' do
    doc = Nokogiri::HTML5.fragment(
      '<turbo-cable-stream-source signed-stream-name="not-signed">' \
      'eyJhbGciOiJIUzI1NiJ9.payload</turbo-cable-stream-source>'
    )

    expect { assert_safe!(doc) }.to raise_error(RuntimeError, 'fixture contains a JWT-shaped value')
  end

  it 'writes the layout for each state' do
    travel_to now do
      capture('signed_out_en', '/users/sign_in', { user: nil, self_hosted: true, accept_language: nil })
      capture('signed_out_de_suggested', '/users/sign_in',
              { user: nil, self_hosted: true, accept_language: 'de-DE,de;q=0.9' },
              { 'Accept-Language' => 'de-DE,de;q=0.9' })

      dark = create(:user, email: 'layout-dark@dawarich.test', theme: 'dark')
      sign_in dark
      capture('self_hosted_dark_en', '/notifications',
              { user: user_state(dark), self_hosted: true, accept_language: nil })
      sign_out dark

      light = create(:user, email: 'layout-light@dawarich.test', theme: 'light')
      light.update_columns(settings: light.settings.merge('locale' => 'de'))
      sign_in light
      capture('self_hosted_light_de', '/notifications',
              { user: user_state(light.reload), self_hosted: true, accept_language: nil })
      sign_out light

      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      stub_const('SELF_HOSTED', false)
      cloud = create(:user, email: 'layout-cloud@dawarich.test')
      sign_in cloud
      capture('cloud_en', '/notifications', { user: user_state(cloud), self_hosted: false, accept_language: nil })
    end

    flashes = %w[notice success alert error warning info].flat_map do |type|
      %w[en de].map do |locale|
        html = I18n.with_locale(locale) do
          ApplicationController.render(partial: 'shared/flash_message',
                                       locals: { type: type, message: 'Gespeichert & <b>ok</b>' })
        end
        { type: type, locale: locale, html: html }
      end
    end
    File.write(dir.join('flash_messages.json'), "#{JSON.pretty_generate(flashes)}\n")
  end
end
