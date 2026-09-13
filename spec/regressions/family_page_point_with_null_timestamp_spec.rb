# frozen_string_literal: true

require 'rails_helper'

# points.timestamp and points.lonlat are both nullable and both only guarded by a
# model-level presence validation, which every bulk import path skips by writing
# through upsert_all. An incomplete row sorts ahead of every real point under
# PostgreSQL's ORDER BY timestamp DESC (NULLS FIRST), so it is picked as the
# member's "latest" location and takes the family surfaces down for everyone.
RSpec.describe 'Family location lookup with incomplete points' do
  let(:latest_at) { Time.zone.parse('2026-07-01 12:00') }
  let(:earlier_at) { Time.zone.parse('2026-06-01 12:00') }
  let(:newest_at) { Time.zone.parse('2026-07-15 12:00') }

  let(:owner) { create(:user) }
  let(:family) { create(:family, creator: owner) }

  before do
    create(:family_membership, user: owner, family: family, role: :owner)
    owner.update_family_location_sharing!(true)
    create(:point, user: owner, timestamp: latest_at.to_i)
  end

  # Forces an incomplete row past the model validation the same way upsert_all does.
  # The row must win ORDER BY timestamp DESC to be selected as the latest point:
  # a NULL timestamp sorts first on its own, but a NULL-coordinate row still needs
  # the newest timestamp to get picked.
  def add_incomplete_point(user, at: earlier_at, **columns)
    point = create(:point, user: user, timestamp: at.to_i)
    Point.where(id: point.id).update_all(**columns)
    point
  end

  describe 'the unfiltered relation' do
    it 'places an incomplete row ahead of real points, which is what makes this reachable' do
      add_incomplete_point(owner, timestamp: nil)

      expect(owner.points.order(timestamp: :desc).limit(1).first.timestamp).to be_nil
    end
  end

  context 'when a point has no timestamp' do
    before { add_incomplete_point(owner, timestamp: nil) }

    it 'returns the latest point that actually has a timestamp' do
      result = owner.latest_location_for_family

      expect(result[:timestamp]).to eq(latest_at.to_i)
      expect(result[:updated_at]).to eq(Time.zone.at(latest_at.to_i))
    end

    it 'reports that point through the family locations API' do
      location = Families::Locations.new(owner).call.first

      expect(location[:timestamp]).to eq(latest_at.to_i)
      expect(location[:updated_at]).to eq(Time.zone.at(latest_at.to_i))
    end
  end

  context 'when a point has no coordinates' do
    before { add_incomplete_point(owner, at: newest_at, lonlat: nil) }

    it 'returns the latest point that actually has coordinates' do
      result = owner.latest_location_for_family

      expect(result[:timestamp]).to eq(latest_at.to_i)
      expect(result[:latitude]).to be_present
      expect(result[:longitude]).to be_present
    end

    it 'reports that point through the family locations API' do
      location = Families::Locations.new(owner).call.first

      expect(location[:timestamp]).to eq(latest_at.to_i)
      expect(location[:latitude]).to be_present
      expect(location[:longitude]).to be_present
    end
  end

  context 'when every point is incomplete' do
    it 'drops the member instead of reporting an epoch-zero location' do
      owner.points.update_all(timestamp: nil)

      expect(owner.latest_location_for_family).to be_nil
      expect(Families::Locations.new(owner).call).to be_empty
    end
  end

  context 'when shared history contains a point without coordinates' do
    before do
      owner.update_family_location_sharing!(true, share_history: true, history_window: 'all')
      owner.settings['family']['location_sharing']['started_at'] = earlier_at.iso8601
      owner.save!
      add_incomplete_point(owner, at: newest_at, lonlat: nil)
    end

    it 'omits it instead of emitting a null coordinate pair into the track' do
      history = Families::Locations.new(owner).history(start_at: earlier_at, end_at: newest_at + 1.day)
      points = history.first[:points]

      expect(points).to be_present
      expect(points.map { _1[0] }).to all(be_present)
      expect(points.map { _1[1] }).to all(be_present)
    end
  end

  context 'with several sharing members' do
    let(:relative) { create(:user) }

    before do
      create(:family_membership, user: relative, family: family, role: :member)
      relative.update_family_location_sharing!(true)
      create(:point, user: relative, timestamp: latest_at.to_i)
      add_incomplete_point(owner, timestamp: nil)
    end

    it 'still reports both members' do
      locations = Families::Locations.new(owner).call

      expect(locations.map { _1[:user_id] }).to match_array([owner.id, relative.id])
      expect(locations.map { _1[:timestamp] }).to all(eq(latest_at.to_i))
    end
  end

  describe 'GET /family', type: :request do
    before { sign_in owner }

    it 'renders when a member has a point without a timestamp' do
      add_incomplete_point(owner, timestamp: nil)

      get family_path

      expect(response).to have_http_status(:ok)
    end

    it 'renders when a member has a point without coordinates' do
      add_incomplete_point(owner, at: newest_at, lonlat: nil)

      get family_path

      expect(response).to have_http_status(:ok)
    end
  end
end
