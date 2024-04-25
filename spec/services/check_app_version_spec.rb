# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CheckAppVersion do
  describe '#call' do
    subject(:check_app_version) { described_class.new.call }

    let(:app_version) { File.read('.app_version').strip }

    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    end

    context 'when latest version is newer' do
      before { allow(File).to receive(:read).with('.app_version').and_return('0.9.0') }

      it { is_expected.to be true }
    end

    context 'when latest version is the same' do
      before { allow(File).to receive(:read).with('.app_version').and_return('1.0.0') }

      it { is_expected.to be false }
    end

    context 'when latest version is older' do
      before { allow(File).to receive(:read).with('.app_version').and_return('1.1.0') }

      it { is_expected.to be true }
    end

    context 'when request fails' do
      before do
        allow(Net::HTTP).to receive(:get).and_raise(StandardError)
        allow(File).to receive(:read).with('.app_version').and_return(app_version)
      end

      it { is_expected.to be false }
    end
  end
end
