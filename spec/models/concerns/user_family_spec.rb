# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserFamily do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }

  before do
    create(:family_membership, family: family, user: user, role: :owner)
  end

  describe '#family_sharing_started_at' do
    it 'returns nil when sharing has never been enabled' do
      expect(user.family_sharing_started_at).to be_nil
    end

    it 'returns the timestamp when sharing was enabled' do
      freeze_time do
        user.update_family_location_sharing!(true, duration: '24h')
        expect(user.family_sharing_started_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'returns nil after sharing is disabled' do
      user.update_family_location_sharing!(true, duration: '24h')
      user.update_family_location_sharing!(false)
      expect(user.family_sharing_started_at).to be_nil
    end
  end

  describe '#update_family_location_sharing! sets sharing_started_at' do
    it 'sets started_at when first enabling' do
      user.update_family_location_sharing!(true, duration: '1h')

      started_at = user.settings.dig('family', 'location_sharing', 'started_at')
      expect(started_at).to be_present
    end

    it 'preserves started_at when changing duration' do
      user.update_family_location_sharing!(true, duration: '1h')
      original_started = user.settings.dig('family', 'location_sharing', 'started_at')

      travel_to 30.minutes.from_now do
        user.update_family_location_sharing!(true, duration: '24h')
        new_started = user.settings.dig('family', 'location_sharing', 'started_at')
        expect(new_started).to eq(original_started)
      end
    end

    it 'clears started_at when disabling' do
      user.update_family_location_sharing!(true, duration: '1h')
      user.update_family_location_sharing!(false)

      started_at = user.settings.dig('family', 'location_sharing', 'started_at')
      expect(started_at).to be_nil
    end

    it 'resets started_at when re-enabling after disable' do
      user.update_family_location_sharing!(true, duration: '1h')
      original_started = user.settings.dig('family', 'location_sharing', 'started_at')

      user.update_family_location_sharing!(false)

      travel_to 1.hour.from_now do
        user.update_family_location_sharing!(true, duration: '24h')
        new_started = user.settings.dig('family', 'location_sharing', 'started_at')
        expect(new_started).not_to eq(original_started)
      end
    end
  end

  describe '#family_history_points' do
    let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }

    before do
      travel_to(now)
      user.update_family_location_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      # Set started_at to well in the past so general tests can find their points.
      # The "does not return points from before sharing was enabled" test overrides this.
      user.update!(
        settings: user.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 1.year.ago.iso8601 } }
        )
      )
    end

    after { travel_back }

    it 'returns empty when sharing is disabled' do
      user.update_family_location_sharing!(false)
      result = user.family_history_points(start_at: 1.day.ago, end_at: Time.current)
      expect(result).to be_empty
    end

    it 'returns points within the given date range' do
      # Create points: one inside range, one outside
      create(:point, user: user, timestamp: 6.hours.ago.to_i)
      create(:point, user: user, timestamp: 2.days.ago.to_i)

      result = user.family_history_points(start_at: 1.day.ago, end_at: Time.current)
      expect(result.count).to eq(1)
    end

    it 'does not return points from before sharing was enabled' do
      # Point from before sharing was enabled
      create(:point, user: user, timestamp: 1.hour.ago.to_i)

      # Simulate: sharing was enabled 30 minutes ago
      user.update!(
        settings: user.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 30.minutes.ago.iso8601 } }
        )
      )

      result = user.family_history_points(start_at: 2.hours.ago, end_at: Time.current)
      # The point at 1 hour ago is before started_at (30 min ago), so should be excluded
      expect(result).to be_empty
    end

    it 'caps history at 1 year maximum' do
      # Create a point from 13 months ago
      create(:point, user: user, timestamp: 13.months.ago.to_i)
      # And a recent one
      create(:point, user: user, timestamp: 1.hour.ago.to_i)

      # Set sharing started_at to 2 years ago
      user.update!(
        settings: user.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 2.years.ago.iso8601 } }
        )
      )

      result = user.family_history_points(start_at: 2.years.ago, end_at: Time.current)
      # Only the recent point should be returned (13 months ago is > 1 year)
      expect(result.count).to eq(1)
    end

    it 'returns points ordered by timestamp ascending' do
      p1 = create(:point, user: user, timestamp: 3.hours.ago.to_i)
      p2 = create(:point, user: user, timestamp: 1.hour.ago.to_i)
      p3 = create(:point, user: user, timestamp: 2.hours.ago.to_i)

      result = user.family_history_points(start_at: 1.day.ago, end_at: Time.current)
      expect(result.pluck(:id)).to eq([p1.id, p3.id, p2.id])
    end
  end

  describe '#update_family_location_sharing! history_window validation' do
    it 'accepts valid history_window values' do
      %w[24h 7d 30d all].each do |window|
        user.update_family_location_sharing!(true, duration: 'permanent', history_window: window)
        expect(user.family_history_window).to eq(window)
      end
    end

    it 'rejects invalid history_window and falls back to 24h' do
      user.update_family_location_sharing!(true, duration: 'permanent', history_window: 'invalid')
      expect(user.family_history_window).to eq('24h')
    end

    it 'rejects XSS payloads in history_window' do
      user.update_family_location_sharing!(true, duration: 'permanent', history_window: '<script>alert(1)</script>')
      expect(user.family_history_window).to eq('24h')
    end

    it 'preserves existing valid window when nil is passed' do
      user.update_family_location_sharing!(true, duration: 'permanent', history_window: '30d')
      user.update_family_location_sharing!(true, duration: 'permanent', history_window: nil)
      expect(user.family_history_window).to eq('30d')
    end
  end
end
