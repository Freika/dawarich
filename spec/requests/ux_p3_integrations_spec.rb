# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'UX P3 integration feedback', type: :request do
  let(:user) { create(:user) }
  let(:credentials) { { 'photoprism_url' => 'https://photoprism.test', 'photoprism_api_key' => 'synthetic-key' } }

  before do
    sign_in user
    stub_host_addresses('photoprism.test', '93.184.216.34')
    stub_request(:get, 'https://photoprism.test/api/v1/photos').with(query: hash_including('count' => '1'))
                                                               .to_raise(Errno::ECONNREFUSED)
  end

  def submit(action)
    patch settings_integrations_path,
          params: { service: 'photoprism', connection_action: action, settings: credentials }
  end

  it 'offers separate save and test actions' do
    get settings_integrations_path(service: 'photoprism')
    expect(Nokogiri::HTML(response.body).at_css('[name="connection_action"][value="test"]')).to be_present
    expect(Nokogiri::HTML(response.body).at_css('[name="connection_action"][value="save"]')).to be_present
  end

  it 'tests the draft without saving it and retains the entered fields' do
    original = user.reload.settings.deep_dup
    submit('test')
    expect(user.reload.settings).to eq(original)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Connection failed. Changes have not been saved.', 'value="https://photoprism.test"')
    expect(response.body).not_to include('connect(2)', 'Connection refused')
  end

  it 'saves without a network call and marks changed credentials untested' do
    user.update!(settings: user.settings.merge('photoprism_connection_status' => 'ok'))
    submit('save')
    expect(user.reload.settings).to include(credentials.merge('photoprism_connection_status' => nil))
    expect(WebMock).not_to have_requested(:get, /photoprism.test/)
    follow_redirect!
    expect(response.body).to include('Settings saved. No connection test was run.')
  end

  it 'shows one coherent failure summary after save and test' do
    submit('save_and_test')
    expect(user.reload.settings).to include(credentials.merge('photoprism_connection_status' => 'failed'))
    expect(flash[:notice]).to be_nil
    expect(flash[:alert]).to be_nil
    follow_redirect!
    expect(response.body).to include('Settings saved, but the connection failed.')
    expect(response.body).not_to include('connect(2)', 'Connection refused')
  end

  it 'retests unchanged settings instead of treating save as proof of connectivity' do
    user.update!(settings: user.settings.merge(credentials).merge('photoprism_connection_status' => 'ok'))
    submit('save_and_test')
    expect(user.reload.settings['photoprism_connection_status']).to eq('failed')
    expect(WebMock).to have_requested(:get, /photoprism.test/).once
  end
end

RSpec.describe 'UX P3 integration action boundaries', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it 'rejects unknown actions and services without changing settings' do
    original = user.settings.deep_dup
    %w[unknown trek].each do |service|
      patch settings_integrations_path,
            params: { service: service, connection_action: 'test', settings: { photoprism_url: 'https://example.test' } }
      expect(response).to have_http_status(:bad_request)
    end
    expect(user.reload.settings).to eq(original)
  end

  it 'applies the outbound URL policy to tests without saving or making a request' do
    original = user.settings.deep_dup
    patch settings_integrations_path, params: { service: 'photoprism', connection_action: 'test',
      settings: { photoprism_url: 'http://169.254.169.254', photoprism_api_key: 'synthetic' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(user.reload.settings).to eq(original)
    expect(response.body).to include('Settings could not be used.')
    expect(WebMock).not_to have_requested(:get, /169.254/)
  end

  %w[immich photoprism airtrail teslamate].each do |service|
    it "tests #{service} without persisting credentials or unrelated settings" do
      stub_host_addresses('integration.test', '93.184.216.34')
      tester = { 'immich' => Immich::ConnectionTester, 'photoprism' => Photoprism::ConnectionTester,
                 'airtrail' => AirTrail::ConnectionTester, 'teslamate' => TeslaMate::ConnectionTester }.fetch(service)
      allow_any_instance_of(tester).to receive(:call).and_return(success: true, message: 'verified')
      original = user.settings.deep_dup
      patch settings_integrations_path, params: { service: service, connection_action: 'test',
        settings: { "#{service}_url" => 'https://integration.test', "#{service}_api_key" => 'synthetic',
                    'immich_url' => 'https://integration.test', 'photoprism_url' => 'https://integration.test' } }
      expect(response).to have_http_status(:ok)
      expect(user.reload.settings).to eq(original)
      expect(response.body).to include('Connection verified. Changes have not been saved.')
    end
  end
end
