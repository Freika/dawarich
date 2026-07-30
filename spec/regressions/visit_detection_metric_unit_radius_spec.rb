# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Visit detection search radius for metric distance units' do
  let(:cluster_start) { DateTime.new(2024, 6, 15, 12, 0, 0, Time.zone.formatted_offset) }
  let(:latitude_offset_within_radius) { 0.0003 }

  def user_with_distance_unit(unit)
    create(:user).tap do |user|
      user.update!(settings: user.settings.deep_merge('maps' => { 'distance_unit' => unit }))
    end
  end

  def seed_cluster(user, latitude, longitude)
    nearby = "POINT(#{longitude} #{latitude + latitude_offset_within_radius})"
    create(:point, user:, lonlat: nearby, timestamp: cluster_start)
    create(:point, user:, lonlat: nearby, timestamp: cluster_start + 10.minutes)
    create(:point, user:, lonlat: nearby, timestamp: cluster_start + 20.minutes)
  end

  describe Places::Visits::Create do
    let(:place) { create(:place, user:, latitude: 54.2905245, longitude: 13.0948638) }

    context 'when the distance unit is kilometers' do
      let(:user) { user_with_distance_unit('km') }

      it 'detects a place visit for points inside the detection radius' do
        seed_cluster(user, place.latitude, place.longitude)

        expect { described_class.new(user, [place]).call }.to change { Visit.count }.by(1)
      end
    end

    context 'when the distance unit is miles' do
      let(:user) { user_with_distance_unit('mi') }

      it 'detects a place visit for points inside the detection radius' do
        seed_cluster(user, place.latitude, place.longitude)

        expect { described_class.new(user, [place]).call }.to change { Visit.count }.by(1)
      end
    end
  end

  describe Areas::Visits::Create do
    let(:area) { create(:area, user:, latitude: 52.437, longitude: 13.539, radius: 100) }

    context 'when the distance unit is kilometers' do
      let(:user) { user_with_distance_unit('km') }

      it 'detects an area visit for points inside the area radius' do
        seed_cluster(user, area.latitude, area.longitude)

        expect { described_class.new(user, [area]).call }.to change { Visit.count }.by(1)
      end
    end

    context 'when the distance unit is miles' do
      let(:user) { user_with_distance_unit('mi') }

      it 'detects an area visit for points inside the area radius' do
        seed_cluster(user, area.latitude, area.longitude)

        expect { described_class.new(user, [area]).call }.to change { Visit.count }.by(1)
      end
    end
  end
end
