# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Language setting', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def document(body)
    Nokogiri::HTML(body)
  end

  def choices(body)
    document(body).css('[data-testid="language-choice"]')
  end

  it 'offers every shipped language on the general settings page' do
    get settings_general_index_path

    expect(choices(response.body).map { |c| c.at_css('input[name="locale"]')['value'] }).to eq(%w[en de es fr])
  end

  it 'names each language in its own words' do
    get settings_general_index_path

    names = choices(response.body).map { |c| c.at_css('[data-testid="language-name"]').text.strip }
    expect(names).to eq(%w[English Deutsch Español Français])
  end

  it 'shows a flag beside each language' do
    get settings_general_index_path

    flags = choices(response.body).map { |c| c.at_css('svg') }
    expect(flags).to all(be_present)
    expect(flags.size).to eq(4)
  end

  it 'marks the language the reader is already using' do
    get settings_general_index_path, params: { locale: 'es' }

    checked = choices(response.body).select { |c| c.at_css('input[name="locale"]')['checked'] }
    expect(checked.size).to eq(1)
    expect(checked.first.at_css('input[name="locale"]')['value']).to eq('es')
  end

  it 'saves the chosen language to the account' do
    patch settings_general_path, params: { locale: 'es', timezone: 'Europe/Berlin' }

    expect(user.reload.preferred_locale).to eq(:es)
  end

  it 'shows the interface in the chosen language on the next request' do
    patch settings_general_path, params: { locale: 'de', timezone: 'Europe/Berlin' }
    get settings_general_index_path

    expect(response.body).to include('<html lang="de"')
  end

  it 'ignores a language it does not ship' do
    patch settings_general_path, params: { locale: 'xx', timezone: 'Europe/Berlin' }

    expect(user.reload.preferred_locale).to be_nil
  end

  it 'leaves unrelated settings alone when the language changes' do
    user.update!(settings: user.settings.merge('timezone' => 'Europe/Berlin', 'maps' => { 'distance_unit' => 'km' }))

    patch settings_general_path, params: { locale: 'es', timezone: 'Europe/Berlin' }

    expect(user.reload.settings['maps']).to eq('distance_unit' => 'km')
    expect(user.settings['timezone']).to eq('Europe/Berlin')
  end

  it 'no longer offers the language links in the navbar' do
    get map_path

    expect(document(response.body).css('a[data-testid^="locale-switch-"]')).to be_empty
  end
end
