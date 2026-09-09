# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Version indicator without internet access', type: :helper do
  include ApplicationHelper

  let(:version_url) { 'https://api.github.com/repos/Freika/dawarich/tags' }

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
    stub_const('APP_VERSION', '1.0.0')
    stub_request(:get, version_url).to_timeout
  end

  it 'renders repeated cold-cache checks without contacting GitHub' do
    2.times { expect(new_version_available?).to be false }

    expect(a_request(:get, version_url)).not_to have_been_made
  end

  it 'uses the cached release without contacting GitHub' do
    Rails.cache.write(CheckAppVersion::VERSION_CACHE_KEY, '1.1.0')

    expect(new_version_available?).to be true
    expect(a_request(:get, version_url)).not_to have_been_made
  end
end
