# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::Writers::VisitWriter do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :polarsteps) }
  let(:place) { create(:place, user:, name: 'Cafe') }
  let(:started_at) { Time.zone.parse('2026-02-01 09:00:00') }

  def extracted(name)
    EnhancedImport::Extracted::Visit.new(
      started_at:, ended_at: started_at + 1.hour, place: nil, name:, confidence: nil, source_label: 'polarsteps'
    )
  end

  it 'lets a visit named after its Place follow later Place renames' do
    visit, = described_class.new(user, import).upsert(extracted('Cafe'), place)
    place.update!(name: 'Corner Cafe')

    expect(visit.reload).to have_attributes(name: nil, location_label: 'Cafe', display_name: 'Corner Cafe')
  end

  it 'keeps a visit name that differs from its Place' do
    visit, = described_class.new(user, import).upsert(extracted('Breakfast'), place)

    expect(visit.reload).to have_attributes(name: 'Breakfast', location_label: 'Cafe')
  end
end
