# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnqueueBackgroundJob, type: :job do
  let(:user_id) { 1 }

  context 'when job_name is start_reverse_geocoding' do
    it 'delegates to Jobs::Create' do
      expect(Jobs::Create).to receive(:new).with('start_reverse_geocoding', user_id).and_return(double(call: nil))

      described_class.perform_now('start_reverse_geocoding', user_id)
    end
  end

  context 'when job_name is start_immich_import' do
    it 'enqueues Import::ImmichGeodataJob' do
      expect { described_class.perform_now('start_immich_import', user_id) }
        .to have_enqueued_job(Import::ImmichGeodataJob).with(user_id)
    end
  end

  context 'when job_name is start_photoprism_import' do
    it 'enqueues Import::PhotoprismGeodataJob' do
      expect { described_class.perform_now('start_photoprism_import', user_id) }
        .to have_enqueued_job(Import::PhotoprismGeodataJob).with(user_id)
    end
  end

  context 'when job_name is unknown' do
    it 'raises ArgumentError' do
      expect { described_class.perform_now('invalid_job', user_id) }
        .to raise_error(ArgumentError, 'Unknown job name: invalid_job')
    end
  end
end
