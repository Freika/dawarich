# frozen_string_literal: true

require 'rails_helper'

# Regression: the API settings writer must apply the same SSRF URL blocklist as
# the web Settings::Update, so a cloud user cannot store an internal integration URL.
RSpec.describe 'Users::SettingsUpdater validates integration URLs' do
  let(:user) { create(:user, settings: {}) }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  it 'rejects a loopback immich_url on cloud and does not persist it' do
    result = Users::SettingsUpdater.new(user, { 'immich_url' => 'http://127.0.0.1:9' }).call

    expect(result.success?).to be(false)
    expect(result.error).to match(/not allowed/i)
    expect(user.reload.settings['immich_url']).to be_nil
  end

  it 'accepts a routable public immich_url' do
    stub_host_addresses('immich.example.test', '93.184.216.34')

    # dup: params strings are mutable in real requests; User#sanitize_input gsub!s them.
    result = Users::SettingsUpdater.new(user, { 'immich_url' => +'http://immich.example.test' }).call

    expect(result.success?).to be(true)
    expect(user.reload.settings['immich_url']).to eq('http://immich.example.test')
  end
end
