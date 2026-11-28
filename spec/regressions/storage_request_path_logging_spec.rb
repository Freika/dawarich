# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Storage capabilities in request logs' do
  let(:output) { StringIO.new }
  let(:logger) { ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output)) }

  before { allow(Rails).to receive(:logger).and_return(logger) }

  %w[disk blobs blobs/redirect blobs/proxy representations representations/redirect
     representations/proxy].each do |route|
    it "redacts the capability and private filename from #{route} logs without changing the request" do
      path = "/rails/active_storage/#{route}/synthetic-capability/private-trip.gpx"
      env = Rack::MockRequest.env_for("/dawarich#{path}?phrase=synthetic-phrase&signed_id=synthetic-signed-id&signed_blob_id=synthetic-signed-blob&safe=visible")
      env['SCRIPT_NAME'] = '/dawarich'
      env['PATH_INFO'] = path
      env['action_dispatch.parameter_filter'] = Rails.application.config.filter_parameters
      observed_path = nil
      middleware = Rails::Rack::Logger.new(lambda do |request_env|
        observed_path = request_env['PATH_INFO']
        [204, {}, []]
      end)

      response = middleware.call(env)
      response[2].close

      expect(output.string).not_to include('synthetic-capability', 'private-trip.gpx', 'synthetic-phrase',
                                           'synthetic-signed-id', 'synthetic-signed-blob')
      expect(output.string).to include(route, '[FILTERED]', 'safe=visible')
      expect(observed_path).to eq(path)
    end
  end

  it 'redacts a custom storage prefix beneath an application mount' do
    allow(ActiveStorage).to receive(:routes_prefix).and_return('/private-storage')
    env = Rack::MockRequest.env_for('/mounted/private-storage/blobs/synthetic-capability/private-trip.gpx')
    env['SCRIPT_NAME'] = '/mounted'
    env['PATH_INFO'] = '/private-storage/blobs/synthetic-capability/private-trip.gpx'
    middleware = Rails::Rack::Logger.new(->(_env) { [204, {}, []] })
    response = middleware.call(env)
    response[2].close

    expect(output.string).to include('/mounted/private-storage/blobs/[FILTERED]')
    expect(output.string).not_to include('synthetic-capability', 'private-trip.gpx')
  end

  it 'retains ordinary request paths and nonsecret query diagnostics' do
    env = Rack::MockRequest.env_for('/imports?page=2')
    middleware = Rails::Rack::Logger.new(->(_env) { [204, {}, []] })
    response = middleware.call(env)
    response[2].close

    expect(output.string).to include('/imports?page=2')
  end
end
