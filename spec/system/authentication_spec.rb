# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication UI', type: :system do
  let(:user) { create(:user, password: 'password123') }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

    # Configure email for testing
    ActionMailer::Base.default_options = { from: 'test@example.com' }
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = true
    ActionMailer::Base.deliveries.clear
  end

  describe 'Account UI' do
    it 'shows the user email in the UI when signed in' do
      sign_in_user(user)

      expect(page).to have_current_path(map_path)
      expect(page).to have_css('summary', text: user.email)
    end
  end

  describe 'Self-hosted UI' do
    context 'when self-hosted mode is enabled' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        stub_const('SELF_HOSTED', true)
      end

      it 'does not show registration links in the login UI' do
        visit new_user_session_path

        expect(page).not_to have_link('Register')
        expect(page).not_to have_link('Sign up')
        expect(page).not_to have_content('Register a new account')
      end
    end
  end
end
