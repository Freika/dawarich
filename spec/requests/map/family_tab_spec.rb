# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map family tab', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def page
    get map_v2_path
    Nokogiri::HTML(response.body)
  end

  context 'when the user is in a family' do
    before do
      family = create(:family, creator: user)
      create(:family_membership, family: family, user: user, role: :owner)
    end

    it 'adds a family button and tab to the panel' do
      html = page

      expect(html.at_css('[data-testid="map-button-family"][data-tab="family"]')).to be_present
      expect(html.at_css('[data-tab-content="family"]')).to be_present
    end

    it 'keeps everything about the family layer in that tab' do
      html = page
      tab = html.at_css('[data-tab-content="family"]')

      %w[familyToggle familyMembersList familyMembersContainer].each do |target|
        expect(tab.at_css(%([data-maps--maplibre-target="#{target}"]))).to be_present, "#{target} missing"
      end
      expect(tab.at_css(%(a[href="#{family_path}"]))).to be_present
      expect(html.at_css('[data-tab-content="layers"] [data-maps--maplibre-target^="family"]')).to be_nil
    end
  end

  context 'when the user is not in a family' do
    it 'shows neither the button nor the tab' do
      html = page

      expect(html.at_css('[data-testid="map-button-family"]')).to be_nil
      expect(html.at_css('[data-tab-content="family"]')).to be_nil
      expect(html.at_css('[data-maps--maplibre-target="familyToggle"]')).to be_nil
    end
  end

  context 'when the family plan has lapsed on Cloud' do
    let(:user) { create(:user, plan: :lite) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      family = create(:family, creator: user)
      create(:family_membership, family: family, user: user, role: :owner)
    end

    it 'shows neither the button nor the tab' do
      html = page

      expect(html.at_css('[data-testid="map-button-family"]')).to be_nil
      expect(html.at_css('[data-tab-content="family"]')).to be_nil
    end
  end
end
