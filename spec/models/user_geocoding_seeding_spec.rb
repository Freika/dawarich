# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'geocoding seeding' do
  it 'does not create per-user geocoding settings, even with a provider in the environment' do
    allow(DawarichSettings).to receive_messages(self_hosted?: true, reverse_geocoding_enabled?: true,
                                                photon_enabled?: true, photon_use_https?: true)
    stub_const('PHOTON_API_HOST', 'photon.env.example.com')

    user = create(:user)

    expect(user.service_settings.service_geocoding).to be_empty
  end
end
