# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TCX import of Google Takeout shaped exports' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }

  describe 'a short export where some trackpoints have no Position' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/tcx/google_takeout_2022.tcx').to_s
    end

    it 'imports every trackpoint that carries GPS and skips the rest' do
      expect { Tcx::Importer.new(import, user.id, file_path).call }.not_to raise_error

      expect(user.points.count).to eq(11)
      expect(user.points.pluck(:timestamp)).to all(be_positive)
    end
  end

  describe 'a longer export with 138 trackpoints' do
    let(:file_path) do
      Rails.root.join('spec/fixtures/files/tcx/google_takeout_2019.tcx').to_s
    end

    it 'imports one point per trackpoint that carries GPS' do
      expect { Tcx::Importer.new(import, user.id, file_path).call }.not_to raise_error

      expect(user.points.count).to eq(136)
    end
  end
end
