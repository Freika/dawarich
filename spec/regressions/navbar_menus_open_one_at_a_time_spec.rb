# frozen_string_literal: true

require 'rails_helper'

# The navbar menus are <details> elements. Details that share a name form an
# exclusive group in the browser: opening one closes the others.
RSpec.describe 'Navbar menus open one at a time', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def navbar
    get trips_path
    Nokogiri::HTML(response.body).at_css('.navbar')
  end

  def top_level_menus
    navbar.css('details').reject { |menu| menu.ancestors('details').any? }
  end

  it 'groups every top-level menu, so opening one closes the others' do
    menus = top_level_menus

    expect(menus.size).to be > 1
    expect(menus.map { |menu| menu['name'] }.uniq).to eq(['navbar-menu'])
  end

  it 'keeps the mobile menu open when one of its submenus opens' do
    submenus = navbar.css('details details')

    expect(submenus).not_to be_empty
    submenus.each do |submenu|
      expect(submenu['name']).to be_present
      expect(submenu['name']).not_to eq(submenu.ancestors('details').first['name'])
    end
  end
end
