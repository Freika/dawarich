# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GeofenceEvent do
  it 'keeps synthetic test events out of the real scope' do
    real = create(:geofence_event)
    create(:geofence_event, user: real.user, place: real.place, synthetic: true)

    expect(described_class.real).to contain_exactly(real)
  end

  it 'requires an event type, source and times' do
    event = described_class.new

    expect(event).not_to be_valid
    expect(event.errors.attribute_names).to include(:event_type, :source, :occurred_at, :received_at)
  end
end
