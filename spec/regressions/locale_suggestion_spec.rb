# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Browser language suggestion', type: :request do
  def rendered_locale(body)
    body[/<html lang="(\w+)"/, 1]
  end

  def suggestion(body)
    Nokogiri::HTML(body).at_css('[data-testid="locale-suggestion"]')
  end

  it 'never switches language on its own' do
    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(rendered_locale(response.body)).to eq('en')
  end

  it 'offers the browser language instead of applying it' do
    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    banner = suggestion(response.body)
    expect(banner).to be_present
    expect(banner.text).to include('Deutsch')
    expect(banner.at_css('a')['href']).to eq('/?locale=de')
  end

  it 'writes the suggestion in the language being offered' do
    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(suggestion(response.body).text).to include(I18n.t('shared.locale_suggestion.message', locale: :de))
  end

  it 'stays quiet when the browser already matches the interface' do
    get root_path, headers: { 'Accept-Language' => 'en-US,en;q=0.9' }

    expect(suggestion(response.body)).to be_nil
  end

  it 'stays quiet when the visitor already picked a language this session' do
    get root_path, params: { locale: 'en' }, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }
    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(suggestion(response.body)).to be_nil
  end

  it 'stays quiet when the account already has a saved language' do
    user = create(:user, settings: { 'locale' => 'en' })
    sign_in user

    get root_path, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(suggestion(response.body)).to be_nil
  end

  it 'keeps the offer on the page the visitor is actually reading' do
    get new_user_session_path, params: { foo: 'bar' }, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(suggestion(response.body).at_css('a')['href']).to eq('/users/sign_in?foo=bar&locale=de')
  end

  it 'applies the language when the offer is accepted' do
    get root_path, params: { locale: 'de' }, headers: { 'Accept-Language' => 'de-DE,de;q=0.9' }

    expect(rendered_locale(response.body)).to eq('de')
    expect(suggestion(response.body)).to be_nil
  end
end
