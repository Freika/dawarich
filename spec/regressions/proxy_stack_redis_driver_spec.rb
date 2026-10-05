# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'

RSpec.describe 'Proxy stack Redis driver' do
  it 'uses network Redis for the stand and keeps fakeredis for ordinary tests' do
    script = <<~RUBY
      require 'bundler/setup'
      Bundler.require(:test)
      require 'redis'
      print Redis::Connection.drivers.last.name
    RUBY

    { '1' => 'Redis::Connection::Ruby', nil => 'Redis::Connection::Memory' }.each do |flag, driver|
      output, errors, status = Open3.capture3(
        { 'E2E_PROXY_STACK' => flag }, RbConfig.ruby, '-e', script,
        chdir: File.expand_path('../..', __dir__)
      )

      expect(status).to be_success, errors
      expect(output).to eq(driver)
    end
  end
end
