# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detection::Persister do
  let(:user) { create(:user) }
  let(:policy) { Visits::Detection::Policy.for(user) }
  let(:base_ts) { 1_700_000_000 }
  let(:window_start) { base_ts - 3600 }
  let(:window_end) { base_ts + (24 * 3600) }
  let(:lat0) { 51.3402 }
  let(:lon0) { 12.3712 }

  def stay(start_s, end_s, name: 'Somewhere', place: nil, area: nil, point_ids: [], **extra)
    {
      start_ts: base_ts + start_s, end_ts: base_ts + end_s,
      duration_s: end_s - start_s, center_lat: lat0, center_lon: lon0,
      radius: 20, count: [point_ids.size, 3].max, bridged_s: 0, corroborated: false,
      name: name, place: place, area: area, evidence: name ? :poi : :none,
      point_ids: point_ids
    }.merge(extra)
  end

  def persist(stays, points_by_id: {})
    described_class.new(user, start_at: window_start, end_at: window_end, policy: policy)
                   .call(stays, points_by_id: points_by_id)
  end

  def visit_row(start_s, end_s, status: :suggested, deleted_at: nil, detection_version: nil)
    create(:visit, user: user, status: status, deleted_at: deleted_at,
                   detection_version: detection_version,
                   started_at: Time.zone.at(base_ts + start_s),
                   ended_at: Time.zone.at(base_ts + end_s), duration: (end_s - start_s) / 60)
  end

  it 'creates suggested visits stamped with the detection version and fills the point cache' do
    points = create_list(:point, 3, user: user)

    created = persist([stay(0, 3600, point_ids: points.map(&:id))])

    expect(created.size).to eq(1)
    visit = created.first
    expect(visit.status).to eq('suggested')
    expect(visit.detection_version).to eq(Visits::Detection::VERSION)
    expect(visit.duration).to eq(60)
    expect(points.each(&:reload).map(&:visit_id).uniq).to eq([visit.id])
  end

  it 'is idempotent: the same input twice yields the identical visit set (I3)' do
    stays = [stay(0, 3600), stay(7200, 10_800, name: 'Elsewhere')]

    persist(stays)
    first_run = user.visits.order(:started_at).pluck(:started_at, :ended_at, :name, :status)
    persist(stays)
    second_run = user.visits.order(:started_at).pluck(:started_at, :ended_at, :name, :status)

    expect(second_run).to eq(first_run)
    expect(user.visits.count).to eq(2)
  end

  it 'replaces stale machine output in the window' do
    stale = visit_row(0, 1800)

    persist([stay(7200, 10_800)])

    expect(Visit.exists?(stale.id)).to be(false)
    expect(user.visits.active.count).to eq(1)
  end

  it 'never touches confirmed visits and trims machine stays around them' do
    confirmed = visit_row(3600, 7200, status: :confirmed)

    created = persist([stay(3000, 9000)])

    expect(confirmed.reload.status).to eq('confirmed')
    expect(created.size).to eq(1)
    trimmed = created.first
    overlap = [trimmed.ended_at.to_i, base_ts + 7200].min - [trimmed.started_at.to_i, base_ts + 3600].max
    expect(overlap).to be <= 0
  end

  it 'drops a machine stay swallowed by a confirmed anchor' do
    visit_row(0, 7200, status: :confirmed)

    expect(persist([stay(600, 3600)])).to be_empty
  end

  it 'lets tombstones keep their interval dead (I1)' do
    visit_row(0, 3600, deleted_at: Time.zone.at(base_ts))

    created = persist([stay(300, 3300)])

    expect(created).to be_empty
    expect(user.visits.active.where(status: :suggested).count).to eq(0)
  end

  it 'does not steal points that belong to an anchor' do
    confirmed = visit_row(3600, 7200, status: :confirmed)
    anchor_point = create(:point, user: user, visit_id: confirmed.id)

    persist([stay(7500, 11_100, point_ids: [anchor_point.id])])

    expect(anchor_point.reload.visit_id).to eq(confirmed.id)
  end

  it 'drops the colliding row on unique-index conflict and keeps the batch' do
    place = create(:place, user: user)
    colliding = [
      stay(0, 3600, place: place, name: place.name),
      stay(0, 5400, place: place, name: place.name)
    ]

    created = persist(colliding)

    expect(created.size).to eq(1)
    expect(user.visits.count).to eq(1)
  end

  it 'stores confidence when provided' do
    created = persist([stay(0, 3600, confidence: 77, confidence_breakdown: { 'dwell' => 1.0 })])

    expect(created.first.confidence).to eq(77)
    expect(created.first.confidence_breakdown).to eq({ 'dwell' => 1.0 })
  end
end
