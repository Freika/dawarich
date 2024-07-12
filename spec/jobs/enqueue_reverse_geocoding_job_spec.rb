# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnqueueReverseGeocodingJob, type: :job do
  let(:job_name) { 'start_reverse_geocoding' }
  let(:user_id) { 1 }

  it 'calls job creation service' do
    expect(Jobs::Create).to receive(:new).with(job_name, user_id).and_return(double(call: nil))

    EnqueueReverseGeocodingJob.perform_now(job_name, user_id)
  end
end
