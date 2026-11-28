# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Import::UpdatePointsCountJob, type: :job do
  describe '#perform' do
    subject(:perform) { described_class.new.perform(import.id) }

    let(:user) { create(:user) }
    let!(:import) { create(:import, user:, processed: 3) }

    context 'when the import owner is soft-deleted' do
      before { user.mark_as_deleted! }

      it 'skips updating the import' do
        expect { perform }.not_to(change { import.reload.processed })
      end
    end
  end
end
