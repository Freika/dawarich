# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::BackfillAreasIntoPlacesJob, type: :job do
  it 'runs the restartable Areas backfill' do
    backfill = instance_double(Places::AreasBackfill, call: {})
    allow(Places::AreasBackfill).to receive(:new).with(batch_size: 10).and_return(backfill)

    described_class.perform_now(batch_size: 10)

    expect(backfill).to have_received(:call)
  end
end
