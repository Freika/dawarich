# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: Rails 1.16.0 standalone auth pages', type: :request do
  before(:context) { Rails.application.reload_routes! }

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
    allow(User).to receive(:omniauth_providers).and_return([])
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
  %w[en de es fr pl ca zh].each do |locale|
    %w[registration_disabled invitation_sign_in invitation_sign_up cloud_sign_up providers_only providers_with_credentials].each do |name|
      it "records #{name} in #{locale}" do
        invitation = Struct.new(:family, :invited_by, :token, :email).new(
          Struct.new(:name).new('Auth fixture family'),
          Struct.new(:email).new('auth-inviter@example.invalid'),
          'synthetic-auth-invitation', 'auth-invitee@example.invalid'
        )
        case name
        when 'registration_disabled'
          allow(DawarichSettings).to receive(:registration_enabled?).and_return(false)
        when 'invitation_sign_in'
          allow_any_instance_of(Users::SessionsController).to receive(:load_invitation_context) do |controller|
            controller.instance_variable_set(:@invitation, invitation)
          end
        when 'invitation_sign_up'
          allow_any_instance_of(Users::RegistrationsController).to receive(:set_invitation) do |controller|
            controller.instance_variable_set(:@invitation, invitation)
          end
        when 'cloud_sign_up'
          allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
          allow(ENV).to receive(:[]).and_call_original
          allow(ENV).to receive(:[]).with('TURNSTILE_SITE_KEY').and_return('synthetic-sitekey')
        when 'providers_with_credentials'
          allow(User).to receive(:omniauth_providers).and_return([:openid_connect])
        when 'providers_only'
          stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
          allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
          allow(User).to receive(:omniauth_providers).and_return([:openid_connect])
        end
        Rails.application.reload_routes! if name.start_with?('providers_')
        path = name.end_with?('sign_up') ? '/users/sign_up' : '/users/sign_in'
        params = { locale: locale }
        params[:invitation_token] = invitation.token if name.start_with?('invitation')
        get path, params: params
        expect(response).to have_http_status(:ok)
        hero = Nokogiri::HTML5(response.body).at_css('.hero')
        expect(hero).to be_present
        hero.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
        FixtureRecording.verify(Rails.root.join("app-phoenix/test/fixtures/auth/pages/#{name}_#{locale}.html"), hero.to_html)
      end
    end
  end

  %w[en de es fr pl ca zh].each do |locale|
    %w[sign_up_errors password_edit_errors unlock_errors].each do |name|
      it "records #{name} in #{locale}" do
        page = name == 'sign_up_errors' ? '/users/sign_up' : '/users/password/edit?reset_password_token=synthetic-invalid'
        get page, params: { locale: locale }
        token = Nokogiri::HTML5(response.body).at_css('input[name="authenticity_token"]')['value']
        case name
        when 'sign_up_errors'
          post '/users', params: { authenticity_token: token, user: { email: 'bad', password: 'short', password_confirmation: 'different' } }
        when 'password_edit_errors'
          put '/users/password', params: { authenticity_token: token, user: { reset_password_token: 'synthetic-invalid', password: 'short', password_confirmation: 'different' } }
        when 'unlock_errors'
          get '/users/unlock', params: { unlock_token: 'synthetic-invalid' }
        end
        expect(response).to have_http_status(name == 'unlock_errors' ? :ok : :unprocessable_entity)
        hero = Nokogiri::HTML5(response.body).at_css('.hero')
        expect(hero).to be_present
        hero.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
        FixtureRecording.verify(Rails.root.join("app-phoenix/test/fixtures/auth/pages/#{name}_#{locale}.html"), hero.to_html)
      end
    end
  end

  it 'records confirmation route refusals for the non-confirmable User' do
    routes = [['GET', '/users/confirmation/new'], ['GET', '/users/confirmation'], ['POST', '/users/confirmation']]
    routes.each do |method, path|
      expect { Rails.application.routes.recognize_path(path, method: method.downcase.to_sym) }.to raise_error(ActionController::RoutingError)
    end
    FixtureRecording.verify(Rails.root.join('app-phoenix/test/fixtures/auth/pages/confirmation_routes.json'),
      JSON.pretty_generate(routes.map { |method, path| { method: method, path: path, status: 404 } }) + "\n")
  end

end
