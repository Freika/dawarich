# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Distanceable, type: :model do
  describe '.total_distance' do
    it 'uses a relation as SQL input without materializing its point records' do
      user = create(:user)
      create(:point, user:, timestamp: 1_700_000_000, lonlat: 'POINT(13.404954 52.520008)')
      create(:point, user:, timestamp: 1_700_000_060, lonlat: 'POINT(13.064477 52.398862)')
      relation = user.points.order(:timestamp)

      distance = nil
      expect { distance = Point.total_distance(relation, :m) }
        .not_to change(relation, :loaded?)

      expect(distance).to be_within(1_000).of(27_000)
    end
  end
end
