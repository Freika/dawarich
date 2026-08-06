# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale selection', type: :request do
  it 'defaults to English regardless of the browser language' do
    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9,en;q=0.8' }

    expect(response.body).to include('<html lang="en"')
    expect(response.body).to include('The only location history tracker')
    expect(response.body).not_to include('Der einzige Standortverlaufstracker')
  end

  it 'localizes the primary sign-in action' do
    get new_user_session_path, params: { locale: 'de' }

    expect(response.body).to include('value="Anmelden"')
    expect(response.body).not_to include('value="Log in"')
  end

  it 'persists an explicit supported locale in the session' do
    get root_path, params: { locale: 'de' }
    get root_path

    expect(response.body).to include('<html lang="de"')
    expect(response.body).to include('Der einzige Standortverlaufstracker')
  end

  it 'ignores an unsupported explicit locale' do
    get root_path, params: { locale: 'fr' }

    expect(response.body).to include('<html lang="en"')
    expect(response.body).to include('The only location history tracker')
  end

  it 'persists the preference for a signed-in user and lets an explicit choice override it' do
    user = create(:user)
    sign_in user

    get edit_user_registration_path, params: { locale: 'de' }
    expect(user.reload.preferred_locale).to eq(:de)

    get edit_user_registration_path, headers: { 'Accept-Language' => 'en' }
    expect(response.body).to include('<html lang="de"')

    get edit_user_registration_path, params: { locale: 'en' }
    expect(user.reload.preferred_locale).to eq(:en)
    expect(response.body).to include('<html lang="en"')
  end

  it 'leaves a signed-in user in English until they choose otherwise' do
    user = create(:user, settings: { 'timezone' => 'Europe/Berlin' })
    sign_in user

    get edit_user_registration_path, headers: { 'Accept-Language' => 'de' }

    expect(response.body).to include('<html lang="en"')
    expect(user.reload.settings).to eq('timezone' => 'Europe/Berlin')
  end

  it 'preserves a saved preference when the user signs in from a differently configured browser' do
    user = create(:user, password: 'password123456', settings: { 'locale' => 'de' })

    post user_session_path,
         params: { user: { email: user.email, password: 'password123456' } },
         headers: { 'Accept-Language' => 'en' }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.preferred_locale).to eq(:de)
  end
end
