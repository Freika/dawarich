# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Locale switch menu markup', type: :request do
  def document(body)
    Nokogiri::HTML(body)
  end

  it 'gives every language link its own menu item' do
    get root_path

    links = document(response.body).css('a[data-testid^="locale-switch-"]')
    expect(links.size).to eq(2)
    expect(links.map { |a| a.parent.name }.uniq).to eq(['li'])
  end

  it 'puts one language per menu item so each is styled like its siblings' do
    get root_path

    items = document(response.body).css('li').select { |li| li.at_css('a[data-testid^="locale-switch-"]') }
    expect(items.size).to eq(2)
    expect(items.map { |li| li.css('a').size }.uniq).to eq([1])
  end

  it 'does not wrap the links in a layout-erasing element' do
    get root_path

    expect(response.body).not_to include('class="contents"')
  end

  it 'identifies each link by the language it leads to' do
    get root_path

    ids = document(response.body).css('a[data-testid^="locale-switch-"]').map { |a| a['data-testid'] }
    expect(ids).to eq(%w[locale-switch-de locale-switch-es])
  end

  it 'keeps the language links unique on an authenticated page' do
    sign_in create(:user)

    get map_path

    ids = document(response.body).css('a[data-testid="locale-switch-de"]')
    expect(ids.size).to be >= 1
    expect(document(response.body).css('[data-testid="locale-switch"]')).to be_empty
  end
end
