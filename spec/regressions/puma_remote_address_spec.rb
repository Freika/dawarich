# frozen_string_literal: true

require 'spec_helper'
require 'puma'
require 'puma/configuration'

RSpec.describe 'config/puma.rb client address' do
  def remote_address(marker)
    previous = ENV.fetch('DAWARICH_BEHIND_PHOENIX', nil)
    marker.nil? ? ENV.delete('DAWARICH_BEHIND_PHOENIX') : ENV['DAWARICH_BEHIND_PHOENIX'] = marker
    config = Puma::Configuration.new({ config_files: [File.expand_path('../../config/puma.rb', __dir__)] }, {}, ENV)
    config.clamp
    [config.options[:remote_address], config.options[:remote_address_header]]
  ensure
    previous.nil? ? ENV.delete('DAWARICH_BEHIND_PHOENIX') : ENV['DAWARICH_BEHIND_PHOENIX'] = previous
  end

  it 'takes REMOTE_ADDR from the header Phoenix sets when Phoenix started Puma' do
    expect(remote_address('1')).to eq([:header, 'HTTP_X_DAWARICH_REMOTE_ADDR'])
  end

  it 'keeps the socket address when Puma runs on its own' do
    expect(remote_address(nil)).to eq([:socket, nil])
  end

  it 'ignores any other value of the marker' do
    expect(remote_address('true')).to eq([:socket, nil])
  end
end
