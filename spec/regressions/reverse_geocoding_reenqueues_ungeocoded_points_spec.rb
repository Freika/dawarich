# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Reverse geocoding re-enqueue after an ungeocoded run', type: :job do
  let(:user) { create(:user) }
  let!(:point) { create(:point, user:, country: nil, city: nil, reverse_geocoded_at: nil) }

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    Sidekiq.redis { |r| r.keys('geocode:enq:*').each { |k| r.del(k) } }
  end

  it 're-enqueues a still-ungeocoded point on a later continue run' do
    Jobs::Create.new('continue_reverse_geocoding', user.id).call

    allow(Geocoder).to receive(:search).and_raise(Geocoder::LookupTimeout)
    ReverseGeocodingJob.new.perform('Point', point.id)

    expect(point.reload.reverse_geocoded_at).to be_nil

    expect do
      Jobs::Create.new('continue_reverse_geocoding', user.id).call
    end.to have_enqueued_job(ReverseGeocodingJob).with('Point', point.id, force: false)
  end
end
