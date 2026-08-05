# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locales', type: :request do
  before do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
  end

  it 'uses the best supported browser language on a first visit' do
    get new_user_session_path, headers: { 'Accept-Language' => 'en;q=0.4, fr-CA;q=0.9, de;q=1.0' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<html lang="fr"')
    expect(response.body).to include('value="Se connecter"')
  end

  it 'saves a negotiated language after login for later background email' do
    user = create(:user, password: 'password123456')

    post user_session_path,
         params: { user: { email: user.email, password: 'password123456' } },
         headers: { 'Accept-Language' => 'fr-FR, en;q=0.8' }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.preferred_locale).to eq(:fr)

    mail = UsersMailer.with(user:).archival_approaching
    expect(mail.subject).to eq('Conservez toute votre histoire — passez à Pro')
  end

  it 'saves a negotiated language when the account settings container is malformed' do
    user = create(:user, password: 'password123456')
    user.update_column(:settings, [])

    post user_session_path,
         params: { user: { email: user.email, password: 'password123456' } },
         headers: { 'Accept-Language' => 'fr-FR, en;q=0.8' }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.settings).to eq('locale' => 'fr')
    expect(user.preferred_locale).to eq(:fr)
  end

  it 'saves a negotiated language on a newly created account' do
    stub_const('ALLOW_EMAIL_PASSWORD_REGISTRATION', true)

    expect do
      post user_registration_path,
           params: {
             user: {
               email: 'nouveau@example.com',
               password: 'password123456',
               password_confirmation: 'password123456'
             }
           },
           headers: { 'Accept-Language' => 'fr-FR, en;q=0.8' }
    end.to change(User, :count).by(1)

    expect(User.find_by!(email: 'nouveau@example.com').preferred_locale).to eq(:fr)
  end

  it 'persists an explicit language choice across requests' do
    patch locale_path,
          params: { locale: 'fr' },
          headers: { 'HTTP_REFERER' => new_user_session_url }

    expect(response).to redirect_to(new_user_session_url)
    expect(response).to have_http_status(:see_other)
    expect(cookies[:locale]).to eq('fr')

    get new_user_session_path, headers: { 'Accept-Language' => 'en' }

    expect(response.body).to include('<html lang="fr"')
    expect(response.body).to include('value="Se connecter"')
  end

  it 'saves a signed-in user language preference' do
    user = create(:user)
    sign_in user

    patch locale_path,
          params: { locale: 'fr' },
          headers: { 'HTTP_REFERER' => settings_general_index_url }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.preferred_locale).to eq(:fr)

    cookies[:locale] = 'en'
    get settings_general_index_path, headers: { 'Accept-Language' => 'en' }

    expect(response.body).to include('<html lang="fr"')
    expect(response.body).to include('Paramètres généraux')
  end

  it 'saves an explicit preference when the account settings container is malformed' do
    user = create(:user)
    user.update_column(:settings, [])
    sign_in user.reload

    patch locale_path,
          params: { locale: 'fr' },
          headers: { 'HTTP_REFERER' => settings_general_index_url }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.settings).to eq('locale' => 'fr')
    expect(user.preferred_locale).to eq(:fr)
  end

  it 'falls back safely when a signed-in account has a malformed saved locale' do
    user = create(:user, settings: { 'locale' => false })
    sign_in user

    expect { get settings_general_index_path }.not_to raise_error

    expect(response).to be_successful
    expect(response.body).to include('<html lang="en"')
  end

  it 'applies an explicit signed-out choice to the account after login' do
    user = create(:user, password: 'password123456', settings: { 'locale' => 'en' })

    patch locale_path,
          params: { locale: 'fr' },
          headers: { 'HTTP_REFERER' => new_user_session_url }

    post user_session_path,
         params: { user: { email: user.email, password: 'password123456' } },
         headers: { 'Accept-Language' => 'en' }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.preferred_locale).to eq(:fr)

    get settings_general_index_path, headers: { 'Accept-Language' => 'en' }

    expect(response.body).to include('<html lang="fr"')
    expect(response.body).to include('Paramètres généraux')
  end

  it 'does not let an unmarked stale cookie rewrite the saved account preference' do
    user = create(:user, password: 'password123456', settings: { 'locale' => 'en' })
    cookies[:locale] = 'fr'

    post user_session_path,
         params: { user: { email: user.email, password: 'password123456' } },
         headers: { 'Accept-Language' => 'fr' }

    expect(response).to have_http_status(:see_other)
    expect(user.reload.preferred_locale).to eq(:en)

    get settings_general_index_path

    expect(response.body).to include('<html lang="en"')
    expect(response.body).to include('General settings')
  end

  it 'renders an accessible language selector for signed-out users' do
    get new_user_session_path

    document = Nokogiri::HTML(response.body)
    selector = document.at_css('summary[aria-label="Language: English"]')

    expect(selector).to be_present
    choices = document.css('form[action="/locale"] input[name="locale"]').map { |input| input['value'] }
    expect(choices.tally).to eq('en' => 2, 'fr' => 2)

    navigation_disclosure = document.at_css('summary[aria-label="Open navigation menu"]')
    expect(navigation_disclosure).to be_present
    expect(navigation_disclosure['aria-haspopup']).to be_nil
    expect(navigation_disclosure['aria-controls']).to eq('mobile-navigation-menu')
    expect(document.at_css('#mobile-navigation-menu')).to be_present
    expect(navigation_disclosure.ancestors('details').first['class'].split).to include('xl:hidden')
  end

  it 'marks each autonym with the language it is written in' do
    get new_user_session_path, headers: { 'Accept-Language' => 'fr' }

    document = Nokogiri::HTML(response.body)
    selectors = document.css('form[action="/locale"] span[lang]')

    expect(document.at_css('summary[aria-label="Langue : Français"]')).to be_present
    expect(selectors.map { |label| [label['lang'], label.text] }.uniq)
      .to contain_exactly(%w[en English], %w[fr Français])
  end

  it 'rejects unsupported language choices' do
    patch locale_path, params: { locale: 'de' }

    expect(response).to have_http_status(:unprocessable_content)
    expect(cookies[:locale]).to be_nil
  end
end
