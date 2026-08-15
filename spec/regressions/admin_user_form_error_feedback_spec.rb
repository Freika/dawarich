# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin user management error feedback', type: :request do
  let!(:admin) { create(:user, :admin) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    sign_in admin
  end

  describe 'creating a user with an invalid password' do
    it 'redirects with a followable status and explains the failure' do
      post settings_users_url, params: { user: { email: 'new@user.com', password: 'short' } }

      expect(response).to have_http_status(:see_other)

      follow_redirect!

      expect(response.body).to match(/password/i)
    end
  end

  describe 'updating a user with an invalid email' do
    it 'redirects with a followable status and explains the failure' do
      user = create(:user)

      patch settings_user_url(user), params: { user: { email: '' } }

      expect(response).to have_http_status(:see_other)

      follow_redirect!

      expect(response.body).to match(/email/i)
    end
  end
end
