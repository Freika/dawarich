# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::DestroyJob do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :gpx) }

  describe 'Oban-owned forwarding' do
    it 'a GPX import without visits or tracks forwards' do
      job_owner!('command:enhanced_import.destroy_gpx', :oban)
      allow(EnhancedImport::Destroy).to receive(:new)
      allow(EnhancedImport::CardBroadcaster).to receive(:call)

      described_class.new.perform(import.id)

      row = JobOutbox.sole
      expect(row.payload).to eq('import_id' => import.id)
      expect(EnhancedImport::Destroy).not_to have_received(:new)
      expect(EnhancedImport::CardBroadcaster).not_to have_received(:call)
    end

    it 'a GPX import owning a visit runs Rails instead of forwarding' do
      job_owner!('command:enhanced_import.destroy_gpx', :oban)
      create(:visit, user: user).update_columns(import_id: import.id)
      destroyer = instance_double(EnhancedImport::Destroy, call: true)
      allow(EnhancedImport::Destroy).to receive(:new).with(import).and_return(destroyer)

      described_class.new.perform(import.id)

      expect(JobOutbox.count).to eq(0)
      expect(destroyer).to have_received(:call)
    end
  end
end
