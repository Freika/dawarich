# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Enhanced import is idempotent on re-runs' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :google_phone_takeout) }

  let(:place) do
    EnhancedImport::Extracted::Place.new(
      external_place_id: 'google:ChIJ_TEST_HOME',
      name: 'Home',
      latitude: 52.52,
      longitude: 13.405
    )
  end

  let(:visit) do
    EnhancedImport::Extracted::Visit.new(
      started_at: Time.zone.parse('2025-04-01T10:00:00Z'),
      ended_at:   Time.zone.parse('2025-04-01T13:00:00Z'),
      place: place,
      name: 'Home',
      confidence: 95,
      source_label: 'google_phone_takeout'
    )
  end

  before do
    allow_any_instance_of(EnhancedImport::Translator).to receive(:translate) do |&block|
      block.call(visit)
    end
  end

  it 'inserts exactly one Place and one Visit when run twice' do
    expect { EnhancedImport::ExtractJob.new.perform(import.id) }
      .to change { Place.count }.by(1)
      .and change { Visit.count }.by(1)

    expect { EnhancedImport::ExtractJob.new.perform(import.id) }
      .not_to(change { Place.count + Visit.count })

    expect(import.reload.additional_data_extraction_status).to eq('completed')
  end
end
