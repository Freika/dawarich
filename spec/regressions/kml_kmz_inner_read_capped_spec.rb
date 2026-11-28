# frozen_string_literal: true

require 'rails_helper'
require 'zip'

# Regression: the inner .kml of a KMZ must be inflated under a size cap so a
# crafted KMZ cannot expand unbounded into worker memory.
RSpec.describe 'Kml::Importer caps the inner KMZ read' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'doc.kmz', source: 'kml') }

  let(:kmz_bytes) do
    path = Rails.root.join('tmp', "kmz_#{SecureRandom.hex(4)}.zip").to_s
    ::Zip::File.open(path, create: true) do |z|
      z.get_output_stream('doc.kml') { |o| o.write("<kml>#{'A' * (4 * 1024 * 1024)}</kml>") }
    end
    bytes = File.binread(path)
    File.delete(path)
    bytes
  end

  around do |example|
    prev = ENV['ZIP_MAX_EXTRACTED_SIZE']
    ENV['ZIP_MAX_EXTRACTED_SIZE'] = (1024 * 1024).to_s # 1 MiB cap
    example.run
    prev.nil? ? ENV.delete('ZIP_MAX_EXTRACTED_SIZE') : ENV['ZIP_MAX_EXTRACTED_SIZE'] = prev
  end

  it 'raises instead of reading the whole oversized inner entry' do
    importer = Kml::Importer.new(import, user.id)
    expect { importer.send(:find_kml_in_zip, kmz_bytes) }
      .to raise_error(/inner entry too large/i)
  end
end
