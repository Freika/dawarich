# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TCX import against a real Google Takeout export' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }
  describe 'small 2022 export with 11 GPS points' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/tcx/google_takeout_real_2022.tcx').to_s
    end

    it 'imports without raising' do
      expect { Tcx::Importer.new(import, user.id, file_path).call }.not_to raise_error
      expect(user.points.count).to eq(11)
    end
  end

  describe 'large 2019 export with 138 trackpoints' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/tcx/google_takeout_2019.tcx').to_s
    end

    it 'imports without raising' do
      expect { Tcx::Importer.new(import, user.id, file_path).call }.not_to raise_error
      expect(user.points.count).to be > 100
    end
  end
end
