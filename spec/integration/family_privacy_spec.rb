# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family Privacy Enforcement', type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.local(2026, 3, 13, 12, 0, 0) }
  let(:family) { create(:family) }
  let(:user_a) { family.creator }
  let(:user_b) { create(:user) }

  before do
    travel_to(now)
    create(:family_membership, family: family, user: user_a, role: :owner)
    create(:family_membership, family: family, user: user_b)
    allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(true)
  end

  after { travel_back }

  describe 'sharing lifecycle' do
    it 'exposes location and history when sharing is enabled, hides when disabled' do
      # User A enables sharing
      user_a.update_family_location_sharing!(true, duration: 'permanent', share_history: true)
      user_a.update!(
        settings: user_a.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 1.week.ago.iso8601 } }
        )
      )

      # Create points
      create(:point, user: user_a, timestamp: 3.hours.ago.to_i)
      create(:point, user: user_a, timestamp: 1.hour.ago.to_i)

      # User B can see A's latest location
      locations_service = Families::Locations.new(user_b)
      latest = locations_service.call
      expect(latest.length).to eq(1)

      # User B can see A's history
      history = locations_service.history(start_at: 1.day.ago, end_at: Time.current)
      expect(history.length).to eq(1)
      expect(history.first[:points].length).to eq(2)

      # User A disables sharing
      user_a.update_family_location_sharing!(false)

      # User B sees NOTHING (fresh service to avoid cached associations)
      fresh_service = Families::Locations.new(user_b.reload)
      expect(fresh_service.call).to be_empty
      expect(fresh_service.history(start_at: 1.day.ago, end_at: Time.current)).to be_empty
    end

    it 'resets sharing_started_at on re-enable, hiding pre-disable history' do
      # Enable sharing a week ago
      user_a.update_family_location_sharing!(true, duration: 'permanent')
      user_a.update!(
        settings: user_a.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 1.week.ago.iso8601 } }
        )
      )

      # Create old point
      create(:point, user: user_a, timestamp: 3.days.ago.to_i)

      # Disable then re-enable
      user_a.update_family_location_sharing!(false)

      travel_to 1.minute.from_now do
        user_a.update_family_location_sharing!(true, duration: 'permanent')

        # sharing_started_at should be fresh (now), not the old time
        started_at = user_a.family_sharing_started_at
        expect(started_at).to be_within(2.seconds).of(Time.current)

        # Old points before re-enable should NOT be visible
        history = Families::Locations.new(user_b).history(start_at: 1.week.ago, end_at: Time.current)
        expect(history).to be_empty # The old point is before the new started_at
      end
    end
  end

  describe '1-year cap enforcement' do
    it 'caps history at 1 year even when sharing has been on longer' do
      user_a.update_family_location_sharing!(true, duration: 'permanent', share_history: true, history_window: 'all')
      user_a.update!(
        settings: user_a.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 2.years.ago.iso8601 } }
        )
      )

      # Point from 13 months ago
      create(:point, user: user_a, timestamp: 13.months.ago.to_i)
      # Point from 6 months ago
      create(:point, user: user_a, timestamp: 6.months.ago.to_i)

      history = Families::Locations.new(user_b).history(start_at: 2.years.ago, end_at: Time.current)
      expect(history.length).to eq(1)
      # Only the 6-month-old point should be included
      expect(history.first[:points].length).to eq(1)
    end
  end

  describe 'expired sharing duration' do
    it 'treats expired sharing as disabled' do
      user_a.update_family_location_sharing!(true, duration: '1h')
      user_a.update!(
        settings: user_a.settings.deep_merge(
          'family' => { 'location_sharing' => { 'started_at' => 2.hours.ago.iso8601 } }
        )
      )

      # Simulate expiry by setting expires_at to the past
      user_a.update!(
        settings: user_a.settings.deep_merge(
          'family' => { 'location_sharing' => { 'expires_at' => 30.minutes.ago.iso8601 } }
        )
      )

      create(:point, user: user_a, timestamp: 1.hour.ago.to_i)

      expect(user_a.family_sharing_enabled?).to be false
      expect(Families::Locations.new(user_b).call).to be_empty
      expect(Families::Locations.new(user_b).history(start_at: 1.day.ago, end_at: Time.current)).to be_empty
    end
  end

  describe 'location request → accept flow' do
    it 'accepting a request enables sharing for the target user' do
      result = Families::CreateLocationRequest.new(requester: user_b, target_user: user_a).call
      expect(result.success?).to be true

      request = result.payload[:request]

      # Accept with 24h duration
      user_a.update_family_location_sharing!(true, duration: '24h')
      request.update!(status: :accepted, responded_at: Time.current)

      expect(user_a.family_sharing_enabled?).to be true
      expect(request.reload).to be_accepted
    end
  end

  describe 'cooldown enforcement' do
    it 'expired requests do not count toward cooldown' do
      # Create an expired request 30 minutes ago
      create(:family_location_request,
             requester: user_b, target_user: user_a, family: family,
             status: :expired, created_at: 30.minutes.ago)

      # Should be able to create a new request
      result = Families::CreateLocationRequest.new(requester: user_b, target_user: user_a).call
      expect(result.success?).to be true
    end
  end

  describe 'family membership departure' do
    it 'expires pending requests and disables sharing when member leaves' do
      # User A enables sharing
      user_a.update_family_location_sharing!(true, duration: 'permanent')

      # Create a pending request from A to B
      request = create(:family_location_request,
                       requester: user_a, target_user: user_b, family: family,
                       status: :pending, expires_at: 1.day.from_now)

      # User A leaves the family
      user_a.family_membership.destroy

      # Sharing should be disabled
      expect(user_a.reload.family_sharing_enabled?).to be false

      # Pending requests should be expired
      expect(request.reload).to be_expired
    end
  end
end
