# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::RawData::VerifyRandomJob, type: :job do
  describe '#perform' do
    let(:verifier) { instance_double(Points::RawData::Verifier) }

    before do
      allow(Points::RawData::Verifier).to receive(:new).and_return(verifier)
      allow(verifier).to receive(:verify_specific_archive)
    end

    it 'is enqueued in the archival queue' do
      expect { described_class.perform_later }
        .to have_enqueued_job.on_queue('archival')
    end

    context 'when there are unverified archives' do
      let(:user) { create(:user) }
      let!(:archives) do
        create_list(:points_raw_data_archive, 3, user: user, verified_at: nil)
      end

      it 'verifies unverified archives' do
        expect(verifier).to receive(:verify_specific_archive).at_least(:once)

        described_class.perform_now
      end
    end

    context 'when there are no unverified archives' do
      it 'does nothing' do
        expect(verifier).not_to receive(:verify_specific_archive)

        described_class.perform_now
      end
    end
  end
end
