# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Sign-in with stashed pending import ticket' do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
    allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
    stub_const('MANAGER_URL', 'https://manager.example.com')
  end

  let!(:pending) { create(:pending_import, :with_file) }
  let!(:user) { create(:user, password: 'safepassword') }

  it 'claims the stashed ticket after successful sign-in' do
    get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
    expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)

    expect do
      post '/users/sign_in', params: { user: { email: user.email, password: 'safepassword' } }
    end.to change(user.imports, :count).by(1)
  end
end
