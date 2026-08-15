# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260508093702_backfill_user_id_on_places')

RSpec.describe BackfillUserIdOnPlaces do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }

  def run_migration
    perform_enqueued_jobs { described_class.new.up }
  end

  def userless_place(name)
    place = create(:place, user: owner, name: name)
    place.update_columns(user_id: nil)
    place
  end

  def visit_for(user, place, started_at: 1.day.ago, suggested: false)
    visit = create(:visit, user: user, place: place, area: nil,
                           started_at: started_at, ended_at: started_at + 1.hour)
    create(:place_visit, visit: visit, place: place) if suggested
    visit
  end

  it 'assigns a place reachable only via place_visits to its owning user' do
    place = userless_place('via-place-visits')
    visit_for(owner, place, suggested: true)

    run_migration

    expect(place.reload.user_id).to eq(owner.id)
  end

  it 'assigns a place reachable only via visits.place_id (no place_visits row) to its owning user' do
    place = userless_place('via-visit-place-id')
    visit_for(owner, place, suggested: false)

    run_migration

    expect(place.reload.user_id).to eq(owner.id)
  end

  it 'picks the user with the most linked visits when ownership is contested' do
    place = userless_place('contested')
    3.times { |i| visit_for(owner, place, started_at: (i + 1).days.ago, suggested: true) }
    visit_for(other_user, place, started_at: 10.days.ago, suggested: true)

    run_migration

    expect(place.reload.user_id).to eq(owner.id)
  end

  it 'deletes a truly orphan place (no place_visits and no visits.place_id)' do
    place = userless_place('orphan')

    expect { run_migration }.to change { Place.where(id: place.id).count }.from(1).to(0)
  end

  it 'leaves places that already have a user_id untouched' do
    untouched = create(:place, user: owner, name: 'already-owned')

    run_migration

    expect(untouched.reload.user_id).to eq(owner.id)
  end

  it 'is re-runnable: early returns when no userless places remain' do
    run_migration

    expect { described_class.new.up }.not_to raise_error
  end
end
