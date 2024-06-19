# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Gpx::TrackParser do
  describe '#call' do
    subject(:parser) { described_class.new(import, user.id).call }

    let(:user) { create(:user) }
    let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_single_segment.gpx') }
    let(:raw_data) { Hash.from_xml(File.read(file_path)) }
    let(:import) { create(:import, user:, name: 'gpx_track.gpx', raw_data:) }

    context 'when file exists' do
      context 'when file has a single segment' do
        it 'creates points' do
          expect { parser }.to change { Point.count }.by(301)
        end
      end

      context 'when file has multiple segments' do
        let(:file_path) { Rails.root.join('spec/fixtures/files/gpx/gpx_track_multiple_segments.gpx') }

        it 'creates points' do
          expect { parser }.to change { Point.count }.by(558)
        end
      end
    end
  end
end
