# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Extracted visits record duration in minutes' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :polarsteps) }
  let(:place) { create(:place, user: user) }
  let(:started_at) { Time.zone.parse('2026-02-01 09:00:00') }

  it 'stores three hours as 180, matching every other visit writer' do
    extracted = EnhancedImport::Extracted::Visit.new(
      started_at: started_at,
      ended_at: started_at + 3.hours,
      place: nil,
      name: 'Cafe',
      confidence: nil,
      source_label: 'polarsteps'
    )

    visit, = EnhancedImport::Writers::VisitWriter.new(user, import).upsert(extracted, place)

    expect(visit.duration).to eq(180)
  end

  it 'agrees with Visits::Create for the same window' do
    service = Visits::Create.new(user, {
                                   name: 'Cafe',
                                   latitude: place.latitude,
                                   longitude: place.longitude,
                                   started_at: started_at.iso8601,
                                   ended_at: (started_at + 3.hours).iso8601
                                 })
    service.call

    extracted = EnhancedImport::Extracted::Visit.new(
      started_at: started_at + 1.day,
      ended_at: started_at + 1.day + 3.hours,
      place: nil,
      name: 'Cafe',
      confidence: nil,
      source_label: 'polarsteps'
    )
    extracted_visit, = EnhancedImport::Writers::VisitWriter.new(user, import).upsert(extracted, place)

    expect(extracted_visit.duration).to eq(service.visit.duration)
  end
end
