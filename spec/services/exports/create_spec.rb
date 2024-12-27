# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exports::Create do
  describe '#call' do
    subject(:create_export) { described_class.new(export:, start_at:, end_at:, file_format:).call }

    let(:file_format)     { :json }
    let(:user)            { create(:user) }
    let(:start_at)        { DateTime.new(2021, 1, 1).to_s }
    let(:end_at)          { DateTime.new(2021, 1, 2).to_s }
    let(:export_name)     { "#{start_at.to_date}_#{end_at.to_date}.#{file_format}" }
    let(:export)          { create(:export, user:, name: export_name, status: :created) }
    let(:export_content)  { Points::GeojsonSerializer.new(points).call }
    let(:reverse_geocoded_at) { Time.zone.local(2021, 1, 1) }
    let(:country) { create(:country, name: 'Germany') }
    let(:city) { create(:city, name: 'Berlin', country:) }
    let!(:points) do
      create_list(
        :point, 10,
        :with_known_location,
        user:,
        timestamp: start_at.to_datetime.to_i,
        reverse_geocoded_at:,
        city:,
        country:
      )
    end

    before do
      allow_any_instance_of(Point).to receive(:reverse_geocoded_at).and_return(reverse_geocoded_at)
    end

    it 'writes the data to a file' do
      create_export

      file_path = Rails.root.join('spec/fixtures/files/geojson/export_same_points.json')

      expect(File.read(file_path).strip).to eq(export_content)
    end

    it 'sets the export url' do
      create_export

      expect(export.reload.url).to eq("exports/#{export.name}")
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
        allow(File).to receive(:open).and_raise(StandardError)
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
