# frozen_string_literal: true

require 'rails_helper'

# assign_winners must return Integer IDs so `batch_ids - assigned_ids` leaves
# only true orphans. If it returned strings the subtraction would never match
# and the job would delete places it had just assigned.
RSpec.describe DataMigrations::BackfillPlacesUserIdJob do
  let(:user) { create(:user) }

  around do |example|
    ActiveRecord::Base.connection.execute('ALTER TABLE places ALTER COLUMN user_id DROP NOT NULL')
    example.run
  end

  def orphan_place
    place = create(:place, user: user)
    place.update_columns(user_id: nil)
    place
  end

  it 'computes orphan_ids as Place#delete_all targets that exclude just-assigned places' do
    place_with_visit = orphan_place
    place_without_visit = orphan_place
    create(:place_visit, place: place_with_visit, visit: create(:visit, user: user))

    described_class.perform_now

    expect(place_with_visit.reload.user_id).to eq(user.id)
    expect(Place.where(id: place_without_visit.id)).not_to exist
  end

  it 'returns Integer IDs from assign_winners so batch_ids - assigned_ids is empty after success' do
    place = orphan_place
    create(:place_visit, place: place, visit: create(:visit, user: user))

    job = described_class.new
    assigned = job.send(:assign_winners, [place.id])

    expect(assigned).to eq([place.id])
    expect(assigned.first).to be_a(Integer)
    expect([place.id] - assigned).to be_empty
  end
end
