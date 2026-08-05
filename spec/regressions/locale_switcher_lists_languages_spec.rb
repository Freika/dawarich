# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale switcher with more than two languages', type: :request do
  def switch_links(body)
    Nokogiri::HTML(body).css('a[data-testid^="locale-switch-"]')
  end

  it 'registers every shipped locale' do
    expect(I18n.available_locales).to match_array(%i[en de es])
  end

  it 'offers every language except the one being read' do
    get root_path

    expect(switch_links(response.body).map { |a| a['hreflang'] }).to eq(%w[de es])
  end

  it 'names each language in its own words' do
    get root_path

    expect(switch_links(response.body).map { |a| a.text.strip }).to eq(%w[Deutsch Español])
  end

  it 'drops the language currently being read from the list' do
    get root_path, params: { locale: 'es' }

    links = switch_links(response.body)
    expect(links.map { |a| a['hreflang'] }).to eq(%w[en de])
    expect(links.map { |a| a.text.strip }).to eq(%w[English Deutsch])
  end

  it 'keeps the reader on the page they are on' do
    get new_user_session_path, params: { foo: 'bar' }

    hrefs = switch_links(response.body).map { |a| a['href'] }
    expect(hrefs).to eq(['/users/sign_in?foo=bar&locale=de', '/users/sign_in?foo=bar&locale=es'])
  end

  it 'marks each link with the language it leads to' do
    get root_path

    expect(switch_links(response.body).map { |a| a['lang'] }).to eq(%w[de es])
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
