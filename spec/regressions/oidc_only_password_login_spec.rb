# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Password sign-in on OIDC-only installations', type: :request do
  let(:password) { 'SyntheticPassword123!' }
  let(:user) { create(:user, password:) }

  before do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
    stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
  end

  [false, true].each do |two_factor|
    it "rejects valid credentials without creating a session when two-factor is #{two_factor}" do
      user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: two_factor)

      post user_session_path, params: { user: { email: user.email, password:, remember_me: '1' } }

      expect(response).to redirect_to(root_path)
      expect(cookies['remember_user_token']).to be_blank
      get imports_path
      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.sign_in_count).to eq(0)
    end
  end

  it 'keeps the password form hidden while rejecting direct JSON login requests' do
    get new_user_session_path
    expect(Nokogiri::HTML(response.body).at_css('input[name="user[password]"]')).to be_nil

    post user_session_path, params: { user: { email: user.email, password: } }, as: :json

    expect(response).to redirect_to(root_path)
    get imports_path
    expect(response).to redirect_to(new_user_session_path)
    expect(user.reload.sign_in_count).to eq(0)
  end

  it 'still allows password login when the operator enables it alongside OIDC' do
    stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', true)
    post user_session_path, params: { user: { email: user.email, password: } }

    get imports_path
    expect(response).to have_http_status(:ok)
    expect(user.reload.sign_in_count).to eq(1)
  end

  it 'keeps password login available when OIDC is not configured' do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    post user_session_path, params: { user: { email: user.email, password: } }

    get imports_path
    expect(response).to have_http_status(:ok)
    expect(user.reload.sign_in_count).to eq(1)
  end
end
