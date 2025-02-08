# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CheckAppVersion do
  describe '#call' do
    subject(:check_app_version) { described_class.new.call }

    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

      stub_const('APP_VERSION', '1.0.0')
    end

    context 'when latest version is newer' do
      before { stub_const('APP_VERSION', '0.9.0') }

      it { is_expected.to be true }
    end

    context 'when latest version is the same' do
      it { is_expected.to be false }
    end

    context 'when latest version is older' do
      before { stub_const('APP_VERSION', '1.1.0') }

      it { is_expected.to be true }
    end

    context 'when latest version is not a stable release' do
      before do
        stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
          .to_return(status: 200, body: '[{"name": "1.0.0-rc.1"}]', headers: {})
      end

      it { is_expected.to be false }
    end

    context 'when request fails' do
      before do
        allow(Net::HTTP).to receive(:get).and_raise(StandardError)
        allow(File).to receive(:read).with('.app_version').and_return(APP_VERSION)
      end

      it { is_expected.to be false }
    end
  end
end
