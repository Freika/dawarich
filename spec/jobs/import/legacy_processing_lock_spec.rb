# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::ProcessJob, type: :job do
  let!(:import) { create(:import, source: :owntracks, skip_background_processing: true) }
  let(:job) { described_class.new }

  before do
    import.file.attach(io: File.open(Rails.root.join('spec/fixtures/files/owntracks/2024-03.rec')),
                       filename: '2024-03.rec', content_type: 'application/octet-stream')
  end

  it 'processes a non-GPX import as before while the per-import session lock is held' do
    hold_import_lock("phoenix-import:#{import.id}") { described_class.perform_now(import.id) }
    expect(import.points.count).to eq(9)
    expect(import.reload).to be_completed
  end

  it 'preserves the legacy non-GPX processing of a completed import' do
    import.update!(status: :completed)
    job.perform(import.id)
    expect(import.points.count).to eq(9)
    expect(import.reload).to be_completed
  end
end
