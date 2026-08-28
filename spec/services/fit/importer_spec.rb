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

      it 'does not persist raw_data for imported points' do
        expect(Point.where(import_id: import.id).pluck(:raw_data).uniq).to eq([{}])
      end

      it 'maps activity type from session sport into motion_data' do
        point = Point.where(import_id: import.id).first

        expect(point.motion_data['activity_type']).to eq('cycling')
      end

      it 'imports all records with correct ordering' do
        points = user.points.order(:timestamp)
        expect(points.last.lat).to be_within(0.001).of(52.522)
      end
    end

    context 'with flat-record FIT file (sessions may have no laps, as observed with Garmin Connect exports)' do
      let(:flat_fit_fixture_path) do
        path = Rails.root.join('tmp', "test_flat_#{SecureRandom.hex(4)}.fit").to_s
        generate_flat_record_fit_fixture(path)
        path
      end

      after { File.delete(flat_fit_fixture_path) if File.exist?(flat_fit_fixture_path) }

      before do
        described_class.new(import, user.id, flat_fit_fixture_path).call
      end

      it 'imports points when sessions may have no laps and records are flat on the activity' do
        expect(user.points.count).to eq(3)
      end

      it 'parses coordinates correctly' do
        point = user.points.order(:timestamp).first
        expect(point.lat).to be_within(0.0001).of(52.5200)
        expect(point.lon).to be_within(0.0001).of(13.4050)
      end

      it 'maps activity type from session sport into motion_data' do
        point = Point.where(import_id: import.id).first

        expect(point.motion_data['activity_type']).to eq('cycling')
      end
    end

    context 'with a FIT activity that omits the device_info section' do
      let(:file_path) do
        path = Rails.root.join('tmp', "test_without_device_info_#{SecureRandom.hex(4)}.fit").to_s
        generate_fit_fixture_without_device_info(path)
        path
      end

      after { File.delete(file_path) if File.exist?(file_path) }

      it 'imports its GPS records without inventing persisted device data' do
        expect do
          described_class.new(import, user.id, file_path).call
        end.to change { user.points.count }.by(3)

        expect(import.reload).not_to be_failed
        expect(Fit4Ruby.read(file_path).device_infos).to be_empty
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

    context 'fit4ruby strict-validation overrides' do
      it 'HeartRateZones#check is a no-op on lap_index mismatch' do
        zones = Fit4Ruby::HeartRateZones.new({})
        zones.instance_variable_set(:@lap_index, 0)
        expect { zones.check(1) }.not_to raise_error
      end

      it 'DeviceInfo#check is a no-op when serial_number is missing' do
        info = Fit4Ruby::DeviceInfo.new({})
        info.instance_variable_set(:@device_index, 0)
        info.instance_variable_set(:@manufacturer, 'garmin')
        info.instance_variable_set(:@garmin_product, 'fenix3')
        info.instance_variable_set(:@serial_number, nil)
        expect { info.check(0) }.not_to raise_error
      end

      it 'temporarily tolerates an activity with no device_info section' do
        activity = Fit4Ruby::Activity.new(timestamp: Time.current, total_timer_time: 60)

        expect { activity.check }.not_to raise_error
        expect(activity.device_infos).to be_empty
      end

      it 'leaves existing device_info entries untouched when they are present' do
        activity = Fit4Ruby::Activity.new(timestamp: Time.current, total_timer_time: 60)
        activity.new_device_info(timestamp: Time.current, device_index: 0)
        activity.new_device_info(timestamp: Time.current, device_index: 1)

        expect { activity.check }.not_to raise_error
        expect(activity.device_infos.size).to eq(2)
      end
    end
  end
end
