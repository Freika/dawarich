# frozen_string_literal: true

require 'rails_helper'
require 'rack/mock'

RSpec.describe 'Response ETags' do
  def request(content_type, body, headers = {}, env = {})
    app = ->(_env) { [200, { 'content-type' => content_type }.merge(headers), body] }
    etag = Rails.application.middleware.find { |entry| entry.klass.is_a?(Class) && entry.klass <= Rack::ETag }
    Rack::ConditionalGet.new(etag.build(app)).call(Rack::MockRequest.env_for('/', env))
  end

  it 'skips HTML body hashing while preserving JSON and other automatic validators' do
    %w[application/json text/plain application/octet-stream text/vnd.turbo-stream.html].each do |type|
      status, headers, body = request(type, ['response'])
      expect(status).to eq(200)
      expect(headers['etag']).to be_present
      expect(body).to eq(['response'])
      status, = request(type, ['response'], {}, 'HTTP_IF_NONE_MATCH' => headers['etag'])
      expect(status).to eq(304)
    end

    expect(Digest::SHA256).not_to receive(:new)
    status, headers, body = request('text/html; charset=utf-8', ['<html>csrf-token</html>'])
    expect(status).to eq(200)
    expect(headers).not_to have_key('etag')
    expect(headers['cache-control']).to eq('no-cache')
    expect(body).to eq(['<html>csrf-token</html>'])
  end

  it 'keeps explicit HTML validators and conditional GET without hashing unvalidated HTML' do
    stub_const('EtagProbeController', Class.new(ApplicationController) do
      reset_callbacks(:process_action)

      def index
        fresh_when(etag: 'explicit-page', template: false)
        render html: '<html>page</html>'.html_safe unless performed?
      end
    end)
    explicit = EtagProbeController.action(:index).call(Rack::MockRequest.env_for('/'))[1]['etag']
    status, headers, = request('text/html', ['page'], 'etag' => explicit)
    expect(status).to eq(200)
    expect(headers['etag']).to eq(explicit)
    status, = request('text/html', ['page'], { 'etag' => explicit }, 'HTTP_IF_NONE_MATCH' => explicit)
    expect(status).to eq(304)
    status, headers, = request('text/html', ['page'], 'last-modified' => Time.utc(2026).httpdate)
    expect(status).to eq(200)
    expect(headers['last-modified']).to eq(Time.utc(2026).httpdate)
    expect(headers).not_to have_key('etag')

    _status, headers, = request('text/html', ['page'], {}, 'HTTP_IF_NONE_MATCH' => 'W/"old-token"')
    expect(headers).not_to have_key('etag')
  end
end
