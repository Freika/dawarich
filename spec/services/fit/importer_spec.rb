# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fit::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :fit) }

  # Generate a fresh FIT fixture per test run to avoid ActiveStorage cleanup deleting the shared fixture
  let(:fit_fixture_path) do
    path = Rails.root.join('tmp', "test_cycling_#{SecureRandom.hex(4)}.fit").to_s
    generate_fit_fixture(path)
    path
  end

  after { File.delete(fit_fixture_path) if File.exist?(fit_fixture_path) }

  describe '#call' do
    context 'with valid FIT activity file' do
      let(:file_path) { fit_fixture_path }

      before do
        described_class.new(import, user.id, file_path).call
      end

      it 'creates points from GPS records' do
        expect(user.points.count).to eq(3)
      end

      it 'parses coordinates from the FIT file' do
        point = user.points.order(:timestamp).first
        # fit4ruby converts semicircles to decimal degrees internally;
        # values lose minor precision through the sint32 round-trip
        expect(point.lat).to be_within(0.0001).of(52.5200)
        expect(point.lon).to be_within(0.0001).of(13.4050)
      end

      it 'parses altitude' do
        point = user.points.order(:timestamp).first
        expect(point.altitude).to eq(34.0)
      end

      it 'parses velocity from speed field' do
        point = user.points.order(:timestamp).first
        expect(point.velocity.to_f).to be_within(0.1).of(5.0)
      end

      it 'parses timestamps as integers' do
        point = user.points.order(:timestamp).first
        expect(point.timestamp).to be_a(Integer)
        expect(Time.zone.at(point.timestamp).year).to eq(2024)
      end

      it 'parses heart rate into raw_data' do
        point = user.points.order(:timestamp).first
        expect(point.raw_data['heart_rate']).to eq(140)
      end

      it 'parses cadence into raw_data' do
        point = user.points.order(:timestamp).first
        expect(point.raw_data['cadence']).to eq(80)
      end

      it 'maps activity type from session sport' do
        point = user.points.order(:timestamp).first
        expect(point.raw_data['activity_type']).to eq('cycling')
      end

      it 'imports all records with correct ordering' do
        points = user.points.order(:timestamp)
        expect(points.last.lat).to be_within(0.001).of(52.522)
        expect(points.last.raw_data['heart_rate']).to eq(150)
      end
    end

    context 'with ActiveStorage file (nil file_path)' do
      let(:temp_path) { fit_fixture_path }
      let(:downloader) { instance_double(Imports::SecureFileDownloader, download_to_temp_file: temp_path) }

      before do
        allow(Imports::SecureFileDownloader).to receive(:new).and_return(downloader)
      end

      it 'downloads the file and imports points' do
        described_class.new(import, user.id).call

        expect(Imports::SecureFileDownloader).to have_received(:new).with(import.file)
        expect(user.points.count).to eq(3)
      end
    end

    context 'with corrupted FIT file' do
      it 'sets import to failed without raising' do
        bad_file = Tempfile.new(['bad', '.fit'])
        bad_file.write('not a valid fit file at all')
        bad_file.rewind

        expect do
          described_class.new(import, user.id, bad_file.path).call
        end.not_to raise_error

        expect(import.reload.status).to eq('failed')
        expect(import.error_message).to be_present
      ensure
        bad_file&.close
        bad_file&.unlink
      end
    end
  end

end
