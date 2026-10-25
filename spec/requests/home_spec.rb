# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Homes', type: :request do
  describe 'GET /' do
    it 'sends a visitor straight to the sign-in page' do
      get '/'

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'sends a signed-in user to their map' do
      sign_in create(:user)

      get '/'

      expect(response).to redirect_to(map_v2_path)
    end

    it 'keeps the language a visitor picked through the redirect' do
      get '/', params: { locale: 'de' }
      follow_redirect!

      expect(response.body).to include('<html lang="de"')
    end

    it 'keeps the flash of a request that redirected to the root' do
      user = create(:user)
      sign_in user

      delete destroy_user_session_path
      follow_redirect! while response.redirect?

      expect(request.path).to eq(new_user_session_path)
      expect(response.body).to include(I18n.t('devise.sessions.signed_out'))
    end
  end
end
