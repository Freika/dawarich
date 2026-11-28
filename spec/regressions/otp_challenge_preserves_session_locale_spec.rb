# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OTP challenge preserves the sign-in session locale', type: :request do
  let(:password) { 'synthetic-password-123' }
  let(:user) do
    create(:user, password: password, otp_secret: User.generate_otp_secret, otp_required_for_login: true)
  end

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
  end

  %w[en fr].each do |locale|
    it "keeps the #{locale} OTP page and its Turbo-tracked translations in the chosen language" do
      get new_user_session_path(locale: locale)

      expect(response).to have_http_status(:ok)
      expect(session[:locale]).to eq(locale)
      sign_in_document = Nokogiri::HTML(response.body)
      expect(sign_in_document.at_css('html')['lang']).to eq(locale)
      sign_in_translations = sign_in_document.at_css('head #i18n-translations[data-turbo-track="reload"]')
      expect(sign_in_translations).to be_present

      # The real form posts without a locale parameter and requests a Turbo response.
      post user_session_path,
           params: { user: { email: user.email, password: password } },
           headers: { 'Accept' => 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(session[:otp_user_id]).to eq(user.id)
      challenge_document = Nokogiri::HTML(response.body)
      expect(challenge_document.at_css('input[name="otp_attempt"]')).to be_present

      aggregate_failures 'OTP locale and Turbo reload signature' do
        expect(challenge_document.at_css('html')['lang']).to eq(locale)
        expect(challenge_document.at_css('h1').text).to eq(
          I18n.t('devise.sessions.otp_challenge.two_factor_authentication', locale: locale)
        )
        # Turbo compares outer HTML for tracked head elements and reloads on a mismatch.
        expect(challenge_document.at_css('head #i18n-translations')&.to_html)
          .to eq(sign_in_translations.to_html), "OTP response changed Turbo's tracked translations for #{locale}"
      end
    end
  end

  it 'greets a user without two-factor authentication in their saved language' do
    german_user = create(:user, password: password, settings: { 'locale' => 'de' })

    post user_session_path, params: { user: { email: german_user.email, password: password } }

    expect(flash[:notice]).to eq(I18n.t('devise.sessions.signed_in', locale: :de))
  end
end
