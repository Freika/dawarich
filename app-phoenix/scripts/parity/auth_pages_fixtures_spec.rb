# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: Rails 1.16.0 standalone auth pages', type: :request do
  around do |example|
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
  end

  %w[en de es fr pl ca zh].each do |locale|
    {
      'sign_in' => '/users/sign_in',
      'sign_up' => '/users/sign_up',
      'password_new' => '/users/password/new',
      'password_edit' => '/users/password/edit?reset_password_token=synthetic-reset',
      'unlock_new' => '/users/unlock/new'
    }.each do |name, path|
      it "records #{name} in #{locale}" do
        get path, params: { locale: locale }
        expect(response).to have_http_status(:ok)
        hero = Nokogiri::HTML5(response.body).at_css('.hero')
        expect(hero).to be_present
        hero.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
        FixtureRecording.verify(Rails.root.join("app-phoenix/test/fixtures/auth/pages/#{name}_#{locale}.html"), hero.to_html)
      end
    end
  end
end
