# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale switch menu markup', type: :request do
  def language_links(body)
    Nokogiri::HTML(body).css('a[data-testid^="locale-switch-"]')
  end

  it 'gives every language link its own menu item' do
    get root_path

    links = language_links(response.body)
    expect(links.size).to eq(2)
    expect(links.map { |a| a.parent.name }.uniq).to eq(['li'])
    expect(links.map { |a| a.parent.css('a').size }.uniq).to eq([1])
  end

  # Nokogiri silently repairs `<li><li>…</li></li>`, so the parsed tree looks
  # correct even when the markup is not. Only the raw body catches a caller
  # that wraps the partial again.
  it 'does not nest the language items inside another menu item' do
    get root_path

    expect(response.body).not_to match(/<li>\s*<li[\s>]/)
  end

  it 'identifies each link by the menu it belongs to and the language it leads to' do
    get root_path

    expect(language_links(response.body).map { |a| a['data-testid'] })
      .to eq(%w[locale-switch-guest-de locale-switch-guest-es])
  end

  it 'keeps every language link addressable by a unique test id' do
    sign_in create(:user)

    get map_path

    ids = language_links(response.body).map { |a| a['data-testid'] }
    expect(ids).to eq(ids.uniq)
    expect(ids).to include('locale-switch-mobile-de', 'locale-switch-account-de')
  end

  # The guest navbar sits inline, so the languages live behind one dropdown
  # rather than adding an item apiece as more locales ship.
  it 'folds the guest navbar languages into a single menu item' do
    get root_path

    guest_menu = Nokogiri::HTML(response.body).css('ul.menu-horizontal').last
    items_holding_languages = guest_menu.css('> li').select do |li|
      li.at_css('a[data-testid^="locale-switch-"]')
    end

    expect(items_holding_languages.size).to eq(1)
    expect(items_holding_languages.first.css('details > ul > li > a').size).to eq(2)
  end
end
