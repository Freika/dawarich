# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tcx::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }

  describe '#call' do
    context 'with running activity TCX' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/tcx/running.tcx').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates points only for trackpoints with GPS' do
        expect(user.points.count).to eq(1)
      end

      it 'parses coordinates correctly' do
        point = user.points.order(:timestamp).first
        expect(point.lat).to be_within(0.001).of(52.520)
        expect(point.lon).to be_within(0.001).of(13.405)
      end

      it 'parses timestamps' do
        point = user.points.order(:timestamp).first
        expect(point.timestamp).to eq(Time.zone.parse('2024-01-01T10:00:00Z').to_i)
      end
    end

    context 'with no-GPS TCX (indoor)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/tcx/no_gps.tcx').to_s }

      it 'creates zero points' do
        described_class.new(import, user.id, file_path).call
        expect(user.points.count).to eq(0)
      end
    end
  end
end
