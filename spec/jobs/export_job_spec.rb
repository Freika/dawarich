# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportJob, type: :job do
  let(:export) { create(:export) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.zone.now }

  it 'calls the Exports::Create service class' do
    expect(Exports::Create).to receive(:new).with(export:, start_at:, end_at:).and_call_original

    described_class.perform_now(export.id, start_at, end_at)
  end
end
