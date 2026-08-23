# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale registration', type: :request do
  it 'registers every shipped locale' do
    expect(I18n.available_locales).to match_array(%i[en de es fr ca])
  end

  it 'names every shipped locale in its own words' do
    names = I18n.available_locales.map { |locale| I18n.t('language_name', locale: locale) }

    expect(names).to eq(%w[English Deutsch Español Français Català])
  end

  # Fallbacks are on in production, where a locale missing `language_name`
  # would resolve to the English value and offer itself as "English". Only
  # `fallback: false` lets the default through, and asserting the option is the
  # only way to pin it: enabling fallbacks on the real backend is irreversible
  # and would leak into every later example.
  it 'asks for a language name without falling back to another language' do
    expect(I18n).to receive(:t).with('language_name', hash_including(fallback: false)).and_return('PT')

    expect(ApplicationController.new.send(:locale_native_name, :pt)).to eq('PT')
  end

  it 'suggests Spanish to a Spanish browser without applying it' do
    get root_path, headers: { 'Accept-Language' => 'es-ES,es;q=0.9' }

    banner = Nokogiri::HTML(response.body).at_css('[data-testid="locale-suggestion"]')
    expect(response.body).to include('<html lang="en"')
    expect(banner).to be_present
    expect(banner.at_css('a')['href']).to eq('/?locale=es')
    expect(banner.text).to include(I18n.t('shared.locale_suggestion.message', locale: :es))
  end
end
