# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExportJob, type: :job do
  let(:export) { create(:export) }

  it 'calls the Exports::Create service' do
    expect(Exports::Create).to receive(:new).with(export:).and_call_original

    described_class.perform_now(export.id)
  end

  it 'raises when export is not found' do
    expect { described_class.perform_now(-1) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
