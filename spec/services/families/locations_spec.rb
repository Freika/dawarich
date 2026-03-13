# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Locations do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:other_user) { create(:user) }

  before do
    travel_to(now)
    create(:family_membership, family: family, user: user, role: :owner)
    create(:family_membership, family: family, user: other_user)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
  end

  after { travel_back }

  describe '#call' do
    it 'returns latest locations for sharing members' do
      other_user.update_family_location_sharing!(true, duration: 'permanent')
      create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

      result = described_class.new(user).call
      expect(result.length).to eq(1)
      expect(result.first[:user_id]).to eq(other_user.id)
    end
  end

  describe '#history' do
    context 'when feature is disabled' do
      before { allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false) }

      it 'returns empty array' do
        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result).to eq([])
      end
    end

    context 'when user is not in a family' do
      let(:solo_user) { create(:user) }

      it 'returns empty array' do
        result = described_class.new(solo_user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result).to eq([])
      end
    end

    context 'when family member has sharing enabled' do
      before do
        other_user.update_family_location_sharing!(true, duration: 'permanent')
        other_user.update!(
          settings: other_user.settings.deep_merge(
            'family' => { 'location_sharing' => { 'started_at' => 1.week.ago.iso8601 } }
          )
        )
      end

      it 'returns history points for sharing members' do
        create(:point, user: other_user, timestamp: 3.hours.ago.to_i)
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result.length).to eq(1)
        expect(result.first[:user_id]).to eq(other_user.id)
        expect(result.first[:points].length).to eq(2)
        expect(result.first[:sharing_since]).to be_present
      end

      it 'returns points as [lat, lon, timestamp] arrays' do
        point = create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        point_data = result.first[:points].first
        expect(point_data).to be_an(Array)
        expect(point_data.length).to eq(3)
      end

      it 'does not include current user in results' do
        user.update_family_location_sharing!(true, duration: 'permanent')
        user.update!(
          settings: user.settings.deep_merge(
            'family' => { 'location_sharing' => { 'started_at' => 1.week.ago.iso8601 } }
          )
        )
        create(:point, user: user, timestamp: 1.hour.ago.to_i)
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result.map { _1[:user_id] }).not_to include(user.id)
      end

      it 'returns empty points for members with sharing disabled' do
        other_user.update_family_location_sharing!(false)
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result).to eq([])
      end

      it 'includes email and color info per member' do
        create(:point, user: other_user, timestamp: 1.hour.ago.to_i)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        member = result.first
        expect(member[:email]).to eq(other_user.email)
        expect(member[:email_initial]).to eq(other_user.email.first.upcase)
      end

      it 'caps points at 5000 per member' do
        # Create more than 5000 points
        timestamps = (1..5500).map { |i| (now - i.minutes).to_i }
        points_data = timestamps.map do |ts|
          { user_id: other_user.id, timestamp: ts, lonlat: 'POINT(0 0)', raw_data: '{}' }
        end
        Point.insert_all(points_data)

        result = described_class.new(user).history(start_at: 1.day.ago, end_at: Time.current)
        expect(result.first[:points].length).to be <= 5000
      end
    end
  end
end
