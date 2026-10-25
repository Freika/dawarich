# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PointsHelper, type: :helper do
  describe '#link_to_date' do
    let(:timestamp) { Time.zone.local(2026, 10, 24, 14, 5).to_i }

    it 'renders the date with the locale format by default' do
      expect(helper.link_to_date(timestamp)).to include('>Oct 24, 2026<')
    end

    it 'renders the date with the date preset' do
      html = Users::DateTimePreferences.with(Users::DateTimePreferences.new(date_format: 'dd/mm/yyyy')) do
        helper.link_to_date(timestamp)
      end

      expect(html).to include('>24/10/2026<')
    end
  end
end
