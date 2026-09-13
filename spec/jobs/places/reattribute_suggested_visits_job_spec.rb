# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::ReattributeSuggestedVisitsJob do
  let(:user) { create(:user) }

  it 'delegates to the reattribution service' do
    place = create(:place, user: user)
    service = instance_double(Places::ReattributeSuggestedVisits, call: 2)
    allow(Places::ReattributeSuggestedVisits).to receive(:new)
      .with(user: user, changed_place: place)
      .and_return(service)

    described_class.perform_now(user.id, place.id)

    expect(service).to have_received(:call)
  end

  it 'quietly skips a missing Place or user' do
    expect { described_class.perform_now(user.id, -1) }.not_to raise_error
    expect { described_class.perform_now(-1, -1) }.not_to raise_error
  end

  describe 'Place lifecycle' do
    it 'enqueues after creation and geometry changes, but not a rename' do
      place = nil
      expect { place = create(:place, user: user) }
        .to have_enqueued_job(described_class).with(user.id, kind_of(Integer))

      expect { place.update!(visit_radius: 75) }
        .to have_enqueued_job(described_class).with(user.id, place.id)
      expect { place.update!(name: 'Renamed') }.not_to have_enqueued_job(described_class)
    end

    it 'can be suppressed for bulk migration' do
      expect do
        place = build(:place, user: user)
        place.skip_suggested_visit_reattribution = true
        place.save!
      end.not_to have_enqueued_job(described_class)
    end
  end
end
