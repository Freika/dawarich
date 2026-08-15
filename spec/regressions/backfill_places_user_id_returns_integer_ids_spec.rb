# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillPlacesUserIdJob do
  let(:user) { create(:user) }

  it 'computes orphan_ids as Place#delete_all targets that exclude just-assigned places' do
    place_with_visit = create(:place, user: nil)
    place_without_visit = create(:place, user: nil)
    create(:place_visit, place: place_with_visit, visit: create(:visit, user: user))

    described_class.perform_now

    expect(place_with_visit.reload.user_id).to eq(user.id)
    expect(Place.where(id: place_without_visit.id)).not_to exist
  end

  it 'returns Integer IDs from assign_winners so batch_ids - assigned_ids is empty after success' do
    place = create(:place, user: nil)
    create(:place_visit, place: place, visit: create(:visit, user: user))

    job = described_class.new
    assigned = job.send(:assign_winners, [place.id])

    expect(assigned).to eq([place.id])
    expect(assigned.first).to be_a(Integer)
    expect([place.id] - assigned).to be_empty
  end
end
