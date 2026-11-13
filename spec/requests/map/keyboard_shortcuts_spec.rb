# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Keyboard shortcuts and documentation in the Help menu', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def page_html
    Nokogiri::HTML(response.body)
  end

  it 'lists every map shortcut in a dialog that ? opens' do
    get map_v2_path

    keys = page_html.css('dialog#keyboard-shortcuts kbd').map(&:text)
    expect(keys).to include('T', 'L', '/', 'C', 'S', 'R', '?', '←', '→')
  end

  it 'leaves out the Family key for a user without a family' do
    get map_v2_path

    expect(page_html.css('dialog#keyboard-shortcuts kbd').map(&:text)).not_to include('F')
  end

  it 'opens the shortcut list from the Help menu on the map' do
    get map_v2_path

    expect(page_html.css('[data-testid="help-keyboard-shortcuts"]')).not_to be_empty
  end

  it 'links to the documentation from the Help menu on every page' do
    get imports_path

    docs = page_html.css('a[data-testid="help-documentation"]').map { _1['href'] }
    expect(docs).to include('https://dawarich.app/docs/')
    expect(page_html.css('[data-testid="help-keyboard-shortcuts"]')).to be_empty
  end
end
