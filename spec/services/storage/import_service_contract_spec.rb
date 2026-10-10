# frozen_string_literal: true

require 'active_support/all'
require 'active_storage'
require 'active_storage/service'
require 'active_storage/service/disk_service'
require 'erb'
require 'pathname'
require 'yaml'

RSpec.describe 'Native import storage source contracts' do
  it 'uses Ruby character slices for custom Disk keys' do
    service = ActiveStorage::Service::DiskService.new(root: '/synthetic/storage')
    expect(service.send(:path_for, 'éλab+%.gpx')).to eq('/synthetic/storage/éλ/ab/éλab+%.gpx')
    expect(service.send(:path_for, "e\u0301abcd.gpx")).to eq("/synthetic/storage/e\u0301/ab/e\u0301abcd.gpx")
  end

  [true, false].each do |test_environment|
    it "renders declared Rails storage services with test environment #{test_environment}" do
      env = {
        'AWS_ACCESS_KEY_ID' => 'synthetic', 'AWS_SECRET_ACCESS_KEY' => 'synthetic',
        'AWS_REGION' => 'eu-central-1', 'AWS_BUCKET' => 'synthetic-bucket'
      }
      allow(ENV).to receive(:[]) { |name| env[name] }
      allow(ENV).to receive(:fetch) { |name| env.fetch(name) }
      rails = Class.new
      rails.define_singleton_method(:root) { Pathname.new('/synthetic/rails') }
      rails.define_singleton_method(:application) { Struct.new(:credentials).new({}) }
      rails.define_singleton_method(:env) { Struct.new(:test?).new(test_environment) }
      stub_const('Rails', rails)
      rendered = ERB.new(File.read('config/storage.yml')).result(binding)
      services = YAML.safe_load(rendered)
      expect(services['test']).to eq('service' => 'Disk', 'root' => '/synthetic/rails/tmp/storage')
      expect(services['local']).to eq('service' => 'Disk', 'root' => '/synthetic/rails/storage')
      expect(services.key?('s3')).to eq(!test_environment)
    end
  end
end
