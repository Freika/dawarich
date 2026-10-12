# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShareLinks::HubData do
  let(:user) { create(:user) }

  def timeline_share(owner = user)
    create(:shared_link, user: owner, resource_type: :timeline, resource_id: nil,
                         settings: { 'start_date' => '2026-04-01', 'end_date' => '2026-04-14' },
                         autobuild_trip: false)
  end

  describe '#live_share' do
    it 'returns the active live share' do
      live = create(:shared_link, :live, user: user)
      expect(described_class.new(user).live_share).to eq(live)
    end

    it 'ignores revoked or expired live shares' do
      create(:shared_link, :live, :revoked, user: user)
      create(:shared_link, :live, :expired, user: user)
      expect(described_class.new(user).live_share).to be_nil
    end

    it 'is nil when there is no live share' do
      expect(described_class.new(user).live_share).to be_nil
    end
  end

  describe '#timeline_share' do
    it 'returns the active timeline share' do
      tl = timeline_share
      expect(described_class.new(user).timeline_share).to eq(tl)
    end

    it 'is nil when there is no timeline share' do
      create(:shared_link, :live, user: user)
      expect(described_class.new(user).timeline_share).to be_nil
    end
  end

  describe '#all_shares' do
    it 'returns all active shares newest first' do
      older = create(:shared_link, :live, user: user)
      older.update_column(:created_at, 2.hours.ago)
      newer = timeline_share
      result = described_class.new(user).all_shares
      expect(result.first).to eq(newer)
      expect(result).to include(older)
    end

    it 'excludes revoked, expired, and other users shares' do
      create(:shared_link, :live, :revoked, user: user)
      create(:shared_link, :live, :expired, user: user)
      create(:shared_link, :live, user: create(:user))
      expect(described_class.new(user).all_shares).to be_empty
    end
  end

  describe '#any_shares?' do
    it 'is true when active shares exist' do
      create(:shared_link, :live, user: user)
      expect(described_class.new(user).any_shares?).to be(true)
    end

    it 'is false when none exist' do
      expect(described_class.new(user).any_shares?).to be(false)
    end
  end

  describe 'default dates' do
    it 'parses provided ISO dates' do
      hub = described_class.new(user, start_date: '2026-03-01', end_date: '2026-03-10')
      expect(hub.default_start_date).to eq(Date.new(2026, 3, 1))
      expect(hub.default_end_date).to eq(Date.new(2026, 3, 10))
    end

    it 'falls back to 7 days ago and today on blank or invalid input' do
      hub = described_class.new(user, start_date: 'bogus', end_date: nil)
      expect(hub.default_start_date).to eq(7.days.ago.to_date)
      expect(hub.default_end_date).to eq(Date.current)
    end
  end
end
