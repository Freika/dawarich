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

  it 'preserves imported visits and trims machine stays around them' do
    import = create(:import, user: user)
    imported = visit_row(3600, 7200)
    imported.update_columns(import_id: import.id)

    created = persist([stay(3000, 9000)])

    expect(Visit.exists?(imported.id)).to be(true)
    expect(created.size).to eq(1)
    overlap = [created.first.ended_at.to_i, base_ts + 7200].min -
              [created.first.started_at.to_i, base_ts + 3600].max
    expect(overlap).to be <= 0
  end

  it 'never overlaps any anchor when several anchors overlap one stay' do
    anchors = [visit_row(9000, 9500, status: :confirmed),
               visit_row(9200, 9800, status: :confirmed)]

    created = persist([stay(0, 10_000)])

    expect(created).not_to be_empty
    created.product(anchors).each do |visit, anchor|
      overlap = [visit.ended_at.to_i, anchor.ended_at.to_i].min -
                [visit.started_at.to_i, anchor.started_at.to_i].max
      expect(overlap).to be <= 0
    end
  end

  it 'keeps the longer flank when an anchor sits strictly inside a stay' do
    visit_row(6000, 7200, status: :confirmed)

    created = persist([stay(0, 10_000)])

    expect(created.size).to eq(1)
    expect(created.first.started_at.to_i).to eq(base_ts)
    expect(created.first.ended_at.to_i).to eq(base_ts + 6000)
  end

  it 'rescores a trimmed stay from the trimmed evidence' do
    visit_row(2400, 9800, status: :confirmed)

    created = persist([stay(0, 10_000, confidence: 100, confidence_breakdown: { 'dwell' => 1.0 })])

    expect(created.size).to eq(1)
    expect(created.first.confidence).to be < 100
  end

  it 'drops a machine stay swallowed by a confirmed anchor' do
    visit_row(0, 7200, status: :confirmed)

    expect(persist([stay(600, 3600)])).to be_empty
  end

  it 'leaves demo machine visits alone' do
    demo = visit_row(3600, 7200)
    demo.update_columns(demo: true)

    persist([stay(7200, 10_800)])

    expect(Visit.exists?(demo.id)).to be(true)
  end

  it 'anchors a visit the user annotated and keeps the note attached' do
    noted = visit_row(3600, 7200)
    note = Note.create!(user: user, body: 'great coffee',
                        noted_at: Time.zone.at(base_ts + 3700), attachable: noted)

    persist([stay(3000, 9000)])

    expect(Visit.exists?(noted.id)).to be(true)
    expect(note.reload.attachable_id).to eq(noted.id)
  end

  it 'enqueues cleanup for places referenced only through suggested-place joins' do
    place = create(:place, user: user)
    stale = visit_row(0, 900)
    PlaceVisit.create!(visit: stale, place: place)

    expect { persist([stay(7200, 10_800)]) }
      .to have_enqueued_job(Places::DeleteIfOrphanJob).with(place.id).once
  end

  it 'reclaims late points even when the regenerated rows look identical' do
    points = create_list(:point, 3, user: user)
    ids = points.map(&:id)
    persist([stay(0, 3600, point_ids: ids, confidence: 80)])

    late = create(:point, user: user)
    persist([stay(0, 3600, point_ids: ids + [late.id], confidence: 80)])

    expect(late.reload.visit_id).to be_present
  end

  it 'keeps identical machine rows in place on a no-change re-run' do
    stays = [stay(0, 3600), stay(7200, 10_800, name: 'Elsewhere')]
    persist(stays)

    expect { persist(stays) }
      .not_to(change { user.visits.active.order(:started_at).pluck(:id) })
  end

  it 'treats a declined visit as an anchor' do
    declined = visit_row(3600, 7200, status: :declined)

    created = persist([stay(3000, 9000)])

    expect(Visit.exists?(declined.id)).to be(true)
    overlap = [created.first.ended_at.to_i, base_ts + 7200].min -
              [created.first.started_at.to_i, base_ts + 3600].max
    expect(overlap).to be <= 0
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

  it 'enqueues one place cleanup per distinct place when replacing machine output' do
    place = create(:place, user: user)
    visit_row(0, 900).update_columns(place_id: place.id)
    visit_row(1800, 2700).update_columns(place_id: place.id)

    expect { persist([stay(7200, 10_800)]) }
      .to have_enqueued_job(Places::DeleteIfOrphanJob).with(place.id).once
  end

  it 'clears the point cache and join rows of replaced machine visits' do
    place = create(:place, user: user)
    stale = visit_row(0, 1800)
    point = create(:point, user: user, visit_id: stale.id)
    join = PlaceVisit.create!(visit: stale, place: place)

    persist([stay(7200, 10_800)])

    expect(point.reload.visit_id).to be_nil
    expect(PlaceVisit.exists?(join.id)).to be(false)
  end

  it 'stores confidence when provided' do
    created = persist([stay(0, 3600, confidence: 77, confidence_breakdown: { 'dwell' => 1.0 })])

    expect(created.first.confidence).to eq(77)
    expect(created.first.confidence_breakdown).to eq({ 'dwell' => 1.0 })
  end
end
