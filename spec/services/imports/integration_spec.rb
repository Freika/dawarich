# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Import format integration' do
  describe 'source detection accuracy' do
    it 'detects CSV from file header' do
      path = Rails.root.join('spec/fixtures/files/csv/gpslogger.csv').to_s
      detector = Imports::SourceDetector.new_from_file_header(path)
      expect(detector.detect_source).to eq(:csv)
    end

    it 'detects TCX from file header' do
      path = Rails.root.join('spec/fixtures/files/tcx/running.tcx').to_s
      detector = Imports::SourceDetector.new_from_file_header(path)
      expect(detector.detect_source).to eq(:tcx)
    end

    it 'detects FIT from file header' do
      temp = Tempfile.new(['test', '.fit'])
      generate_fit_fixture(temp.path)
      detector = Imports::SourceDetector.new_from_file_header(temp.path)
      expect(detector.detect_source).to eq(:fit)
    ensure
      temp&.close
      temp&.unlink
    end
  end

  describe 'importer routing via Imports::Create' do
    let(:user) { create(:user) }

    it 'routes csv source and creates points' do
      import = create(:import, user: user, source: :csv)
      file_path = Rails.root.join('spec/fixtures/files/csv/gpslogger.csv')
      import.file.attach(io: File.open(file_path), filename: 'gpslogger.csv', content_type: 'text/csv')

      expect { Imports::Create.new(user, import).call }.to change { import.points.count }.from(0)

      expect(import.reload.status).to eq('completed')
    end

    it 'routes tcx source and creates points' do
      import = create(:import, user: user, source: :tcx)
      file_path = Rails.root.join('spec/fixtures/files/tcx/running.tcx')
      import.file.attach(io: File.open(file_path), filename: 'running.tcx',
                         content_type: 'application/octet-stream')

      expect { Imports::Create.new(user, import).call }.to change { import.points.count }.from(0)

      expect(import.reload.status).to eq('completed')
    end

    it 'routes fit source and creates points' do
      import = create(:import, user: user, source: :fit)
      temp = Tempfile.new(['cycling', '.fit'])
      generate_fit_fixture(temp.path)
      import.file.attach(io: File.open(temp.path), filename: 'cycling.fit',
                         content_type: 'application/octet-stream')

      expect { Imports::Create.new(user, import).call }.to change { import.points.count }.from(0)

      expect(import.reload.status).to eq('completed')
    end
  end
end
