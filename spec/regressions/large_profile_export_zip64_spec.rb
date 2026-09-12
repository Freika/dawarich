# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Large profile export Zip64 archive', type: :service do
  let(:user) { create(:user) }
  let(:export_directory) do
    Rails.root.join('tmp', "#{user.email.gsub(/[^0-9A-Za-z._-]/, '_')}_20241201_123000")
  end

  before do
    allow(Time).to receive(:current).and_return(Time.zone.local(2024, 12, 1, 12, 30, 0))
    allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
    allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))
    allow(Notifications::Create).to receive(:new).and_return(double(call: true))
  end

  after do
    FileUtils.rm_rf(export_directory) if File.directory?(export_directory)
  end

  around do |example|
    original_support = Zip.write_zip64_support
    Zip.write_zip64_support = false
    example.run
    Zip.write_zip64_support = original_support
  end

  it 'enables Zip64 support while writing the archive regardless of the global default' do
    support_during_write = []

    allow(Zip::File).to receive(:open).and_wrap_original do |original, *args, **kwargs, &block|
      support_during_write << Zip.write_zip64_support
      original.call(*args, **kwargs, &block)
    end

    Users::ExportData.new(user).export

    expect(support_during_write).to include(true)
  end
end
