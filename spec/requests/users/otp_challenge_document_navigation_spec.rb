# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OTP challenge document navigation', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    user.otp_secret = User.generate_otp_secret
    user.otp_required_for_login = true
    user.generate_otp_backup_codes!
    user.save!
  end

  it 'keeps document navigation through four failures before the fifth redirect' do
    post user_session_path, params: { user: { email: user.email, password: password } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(session[:otp_user_id]).to eq(user.id)
    expect(session[:otp_challenge_at]).to be_present
    expect_document_challenge

    1.upto(4) do |attempt|
      post user_otp_challenge_path, params: { otp_attempt: 'not-a-code' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to eq('Invalid two-factor code.')
      expect(session[:otp_failed_attempts]).to eq(attempt)
      expect(user.reload.failed_otp_attempts).to eq(attempt)
      expect_document_challenge
    end

    post user_otp_challenge_path, params: { otp_attempt: 'not-a-code' }

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('Too many invalid two-factor codes. Please sign in again.')
    expect(user.reload.failed_otp_attempts).to eq(5)
    expect(session[:otp_user_id]).to be_nil
    expect(session[:otp_challenge_at]).to be_nil
    expect(session[:otp_failed_attempts]).to be_nil
    expect(session[:otp_remember_me]).to be_nil
  end

  def expect_document_challenge
    forms = Nokogiri::HTML(response.body).css('form[action="/users/otp_challenge"]')
    expect(forms.length).to eq(1)
    form = forms.first

    expect(form['data-turbo']).to eq('false')
    expect(form['method']).to eq('post')
    input = form.at_css('input[name="otp_attempt"]')
    expect(input).to be_present
    expect(input['required']).not_to be_nil
    expect(input['maxlength']).to eq('32')
    expect(input['autocomplete']).to eq('one-time-code')
    expect(input['inputmode']).to eq('numeric')
    expect(input['autofocus']).not_to be_nil
    expect(input['placeholder']).to eq('000000')
    expect(input['value'].to_s).to eq('')
    expect(form.at_css('[type="submit"]')).to be_present
  end
end
