# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Point coordinates match between the map and the points list', type: :request do
  include PointsHelper

  let(:user) { create(:user) }
  # More decimals than either surface displays, so rounding is exercised.
  let(:point) do
    create(:point, user: user, lonlat: 'POINT(12.371234567 51.340298765)', timestamp: 1.day.ago.to_i)
  end

  describe 'the shared formatting helper' do
    it 'renders latitude then longitude at a fixed precision' do
      expect(point_coordinates(point)).to eq('51.340299, 12.371235')
    end

    it 'keeps trailing zeros so the text is stable and searchable' do
      round_point = create(:point, user: user, lonlat: 'POINT(12.5 51.25)', timestamp: 2.days.ago.to_i)

      expect(point_coordinates(round_point)).to eq('51.250000, 12.500000')
    end
  end

  # The map requests points with slim=true, which this query serves directly —
  # not through a serializer. Its rows become the feature properties.
  describe 'the slim points payload the map consumes' do
    subject(:row) { Points::SlimCollectionQuery.new(user.points.where(id: point.id)).call.first }

    it 'carries the stored coordinates' do
      expect(row[:latitude].to_f).to be_within(0.0000001).of(51.340298765)
      expect(row[:longitude].to_f).to be_within(0.0000001).of(12.371234567)
    end

    it 'formats to exactly the string the list shows' do
      from_payload = format(
        '%<lat>.6f, %<lon>.6f',
        lat: row[:latitude].to_f,
        lon: row[:longitude].to_f
      )

      expect(from_payload).to eq(point_coordinates(point))
    end
  end

  describe 'the points list' do
    before { sign_in user }

    it 'shows the same coordinate string the helper produces' do
      point

      get points_path

      expect(response.body).to include(point_coordinates(point))
    end
  end
end
