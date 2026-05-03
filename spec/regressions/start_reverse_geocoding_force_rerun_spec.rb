# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Start Reverse Geocoding force-reruns already-geocoded points',
               type: :job do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:already_geocoded_point) do
    create(:point, user: user, reverse_geocoded_at: 1.day.ago,
                   city: 'Old City', country_name: 'Old Country')
  end

  before do
    allow(DawarichSettings).to receive_messages(
      reverse_geocoding_enabled?: true,
      store_geodata?:             true
    )
    allow(Geocoder).to receive(:search).and_return(
      [double(city: 'New City', country: 'New Country', data: { 'address' => {} })]
    )
  end

  it 'invokes Geocoder.search for an already-geocoded point when the user explicitly starts reverse geocoding' do
    perform_enqueued_jobs do
      Jobs::Create.new('start_reverse_geocoding', user.id).call
    end

    expect(Geocoder).to have_received(:search).at_least(:once),
                        'Expected Geocoder.search to be called for an already-geocoded point ' \
                        'when the user clicks "Start Reverse Geocoding" (which promises a full ' \
                        're-run for all points), but it was never called.'
  end
end
