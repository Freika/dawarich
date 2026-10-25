# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dawarich::SidekiqWeb do
  describe '#safe_request?' do
    def safe?(method: 'POST', **headers)
      env = Rack::MockRequest.env_for('http://192.168.1.10:3000/sidekiq/retries', method:)
      headers.each { |name, value| env["HTTP_#{name.to_s.upcase}"] = value }
      described_class.new.safe_request?(env)
    end

    it 'allows GET requests without any headers' do
      expect(safe?(method: 'GET')).to be(true)
    end

    it 'allows a same-origin request that carries Sec-Fetch-Site' do
      expect(safe?(sec_fetch_site: 'same-origin')).to be(true)
    end

    it 'allows a request without Sec-Fetch-Site when Origin matches the app' do
      expect(safe?(origin: 'http://192.168.1.10:3000')).to be(true)
    end

    it 'rejects a request without Sec-Fetch-Site when Origin is another site' do
      expect(safe?(origin: 'http://evil.example')).to be(false)
    end

    it 'rejects a request without Sec-Fetch-Site when Origin differs only by port' do
      expect(safe?(origin: 'http://192.168.1.10:8080')).to be(false)
    end

    it 'rejects a request without Sec-Fetch-Site when Origin differs only by scheme' do
      expect(safe?(origin: 'https://192.168.1.10:3000')).to be(false)
    end

    it 'rejects a request with neither Sec-Fetch-Site nor Origin' do
      expect(safe?).to be(false)
    end

    it 'rejects a cross-site request even when Origin matches the app' do
      expect(safe?(sec_fetch_site: 'cross-site', origin: 'http://192.168.1.10:3000')).to be(false)
    end
  end
end
