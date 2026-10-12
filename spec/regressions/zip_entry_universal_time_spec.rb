# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe 'Zip entries carry a UTC-tagged mtime so cross-TZ extractors do not skew' do
  describe 'Archive::Zipper.wrap' do
    let(:payload_tempfile) do
      tempfile = Tempfile.new(['payload', '.gpx'], binmode: true)
      tempfile.write('<gpx></gpx>')
      tempfile.rewind
      tempfile
    end

    after { payload_tempfile.close! }

    it 'attaches a UniversalTime extra field with mtime equal to the current UTC epoch' do
      before_epoch = Time.now.to_i
      zipped = Archive::Zipper.wrap(payload_tempfile, entry_name: 'ride.gpx')
      after_epoch = Time.now.to_i

      begin
        entry = ::Zip::File.open(zipped.path) { |zf| zf.glob('ride.gpx').first }

        universal_time = entry.extra[:universaltime]
        message = 'Entry must carry a UniversalTime extra field so extractors interpret mtime as UTC.'
        expect(universal_time).not_to(be_nil, message)

        expect(universal_time.mtime.to_i).to be_between(before_epoch, after_epoch).inclusive
      ensure
        zipped.close!
      end
    end
  end

  describe 'Users::ExportData full-archive zip' do
    let(:user) { create(:user) }

    before do
      allow(Users::ExportData::Imports).to receive(:new).and_return(double(call: []))
      allow(Users::ExportData::Exports).to receive(:new).and_return(double(call: []))
      allow(Notifications::Create).to receive(:new).and_return(double(call: true))
    end

    it 'attaches a UniversalTime extra field to every entry in the user-data archive' do
      before_epoch = Time.now.to_i
      export_record = Users::ExportData.new(user).export
      after_epoch = Time.now.to_i

      temp_zip = Rails.root.join('tmp', "regression_#{user.id}.zip")
      File.binwrite(temp_zip, export_record.file.download)

      begin
        ::Zip::File.open(temp_zip) do |zip|
          zip.each do |entry|
            universal_time = entry.extra[:universaltime]
            expect(universal_time).not_to(
              be_nil,
              "Entry #{entry.name} is missing UniversalTime; cross-TZ extractors will skew its mtime."
            )
            expect(universal_time.mtime.to_i).to be_between(before_epoch, after_epoch).inclusive
          end
        end
      ensure
        File.delete(temp_zip) if File.exist?(temp_zip)
      end
    end
  end
end
