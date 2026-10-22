# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppVersionCheckingJob, type: :job do
  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    stub_const('APP_VERSION', '0.9.0')
  end

  it 'refreshes the release displayed by the version indicator' do
    described_class.perform_now

    expect(CheckAppVersion.new.call).to be true
    expect(Rails.cache.read(CheckAppVersion::VERSION_CACHE_KEY)).to eq('1.0.0')
  end

  it 'keeps the last successful release when the background refresh fails' do
    Rails.cache.write(CheckAppVersion::VERSION_CACHE_KEY, '1.0.0')
    stub_request(:get, 'https://api.github.com/repos/Freika/dawarich/tags').to_timeout

    described_class.perform_now

    expect(CheckAppVersion.new.call).to be true
    expect(Rails.cache.read(CheckAppVersion::VERSION_CACHE_KEY)).to eq('1.0.0')
  end
end
