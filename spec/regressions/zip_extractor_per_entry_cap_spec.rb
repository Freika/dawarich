# frozen_string_literal: true

require 'rails_helper'
require 'zip'

# Regression: the extracted-size cap must bound a single entry mid-stream, not
# only the running total after an entry is fully written to disk.
RSpec.describe 'Imports::ZipExtractor enforces the cap mid-entry' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'bomb.zip') }

  let(:zip_path) do
    path = Rails.root.join('tmp', "cap_#{SecureRandom.hex(4)}.zip").to_s
    ::Zip::File.open(path, create: true) do |z|
      z.get_output_stream('a.gpx') { |o| o.write("\0" * (4 * 1024 * 1024)) } # 4 MiB, deflates tiny
    end
    path
  end

  around do |example|
    prev = ENV['ZIP_MAX_EXTRACTED_SIZE']
    ENV['ZIP_MAX_EXTRACTED_SIZE'] = (1024 * 1024).to_s # 1 MiB cap
    example.run
    prev.nil? ? ENV.delete('ZIP_MAX_EXTRACTED_SIZE') : ENV['ZIP_MAX_EXTRACTED_SIZE'] = prev
    File.delete(zip_path) if File.exist?(zip_path)
  end

  it 'raises before writing the whole oversized entry' do
    expect { Imports::ZipExtractor.new(import, user.id, zip_path).call }
      .to raise_error(/Archive too large/)
  end
end
