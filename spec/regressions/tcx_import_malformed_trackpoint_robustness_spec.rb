# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TCX import robustness against malformed trackpoints' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }

  describe 'a Trackpoint with multiple Position siblings' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/tcx/multiple_positions_per_trackpoint.tcx').to_s
    end

    it 'does not raise and imports the well-formed trackpoints' do
      expect { Tcx::Importer.new(import, user.id, file_path).call }.not_to raise_error

      expect(user.points.count).to eq(1)
      point = user.points.first
      expect(point.lat).to be_within(0.001).of(52.530)
      expect(point.lon).to be_within(0.001).of(13.410)
    end
  end
end
