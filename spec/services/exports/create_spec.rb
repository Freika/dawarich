# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exports::Create do
  describe '#call' do
    subject(:create_export) { described_class.new(export:).call }

    let(:file_format)     { :json }
    let(:user)            { create(:user) }
    let(:start_at)        { DateTime.new(2021, 1, 1).to_s }
    let(:end_at)          { DateTime.new(2021, 1, 2).to_s }
    let(:export_name)     { "#{start_at.to_date}_#{end_at.to_date}.#{file_format}" }
    let(:export) do
      create(:export, user:, name: export_name, status: :created, format: file_format, start_at:, end_at:)
    end
    let(:export_content) { Points::GeojsonSerializer.new(points).call }
    let(:reverse_geocoded_at) { Time.zone.local(2021, 1, 1) }
    let!(:points) do
      10.times.map do |i|
        create(:point, :with_known_location,
               user: user,
               timestamp: start_at.to_datetime.to_i + i,
               reverse_geocoded_at: reverse_geocoded_at)
      end
    end

    before do
      allow_any_instance_of(Point).to receive(:reverse_geocoded_at).and_return(reverse_geocoded_at)
    end

    it 'writes the data to a file' do
      create_export

      file_path = Rails.root.join('spec/fixtures/files/geojson/export_same_points.json')

      expect(File.read(file_path).strip).to eq(export_content)
    end

    it 'sets the export file' do
      create_export

      expect(export.reload.file.attached?).to be_truthy
    end

    it 'updates the export status to completed' do
      create_export

      expect(export.reload.completed?).to be_truthy
    end

    it 'creates a notification' do
      expect { create_export }.to change { Notification.count }.by(1)
    end

    context 'when an error occurs' do
      before do
        allow_any_instance_of(Points::GeojsonSerializer).to receive(:call).and_raise(StandardError)
      end

      it 'updates the export status to failed' do
        create_export

        expect(export.reload.failed?).to be_truthy
      end

      it 'creates a notification' do
        expect { create_export }.to change { Notification.count }.by(1)
      end
    end
  end
end
