# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Places::Destroy do
  let(:user) { create(:user) }
  let(:place) { create(:place, user:, name: 'Cafe') }

  it 'keeps showing the last Place name on its visits' do
    visit = create(:visit, user:, place:, name: nil, location_label: 'Cafe')
    place.update!(name: 'Corner Cafe')

    described_class.new(user:, place:).call

    expect(visit.reload).to have_attributes(place_id: nil, display_name: 'Corner Cafe')
  end

  it "refuses another user's Place" do
    expect { described_class.new(user: create(:user), place:).call }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Place.exists?(place.id)).to be(true)
  end

  it 'keeps geofence events and deliveries with the last place name', :place_retention do
    event = create(:geofence_event, user:, place:, place_name: place.name)
    delivery = create(:webhook_delivery, webhook: create(:webhook, user:), geofence_event: event)
    place.update!(name: 'Corner Cafe')

    described_class.new(user:, place:).call

    expect(event.reload).to have_attributes(place_id: nil, place_name: 'Corner Cafe')
    expect(delivery.reload.geofence_event_id).to eq(event.id)
  end
end
