# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AchievementsHelper, type: :helper do
  describe '#region_silhouette' do
    it 'renders detail stroke widths as SVG stroke-width attributes' do
      svg = helper.region_silhouette(path: 'M0 0', details: [{ path: 'M1 1', stroke: '#fff', stroke_width: 0.4 }])
      detail = Nokogiri::HTML.fragment(svg).at_css('path[data-detail]')

      expect(detail['stroke-width']).to eq('0.4')
    end
  end
end
