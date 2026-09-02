# frozen_string_literal: true

require 'rails_helper'

# Covers the flag-on branches of the per-user geocoding form, which T6 and T10
# introduced but left untested.
RSpec.describe 'Settings::Geocoding when the resolver owns geocoding' do
  let(:user) { create(:user) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(InstanceSettings).to receive(:enabled?).and_return(true)
    sign_in user
  end

  it 'refuses to write a per-user service setting' do
    expect do
      patch '/settings/geocoding',
            params: { provider: 'photon', photon: { host: 'user.example.com' } }
    end.not_to change(ServiceSetting, :count)
  end

  it 'explains why rather than silently discarding the input' do
    patch '/settings/geocoding', params: { provider: 'photon', photon: { host: 'user.example.com' } }

    follow_redirect!
    expect(response.body).to include(I18n.t('settings.geocoding.update.instance_managed'))
  end

  it 'shows the instance-managed notice on the integrations pane' do
    get '/settings/integrations', params: { service: 'geocoding' }

    expect(response.body).to include(I18n.t('settings.geocoding.show.instance_managed_notice'))
  end
end
