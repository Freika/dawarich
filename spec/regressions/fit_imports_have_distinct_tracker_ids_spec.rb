# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'FIT imports have distinct tracker IDs' do
  let(:user) { create(:user) }

  it 'assigns a non-blank per-import tracker to every point from each file' do
    imports = Array.new(2) { create(:import, user: user, source: :fit) }

    imports.each_with_index do |import, index|
      Tempfile.create(['activity', '.fit']) do |file|
        generate_fit_fixture(file.path)
        activity = Fit4Ruby.read(file.path)
        activity.records.each { |record| record.position_lat += index * 0.01 }
        Fit4Ruby.write(file.path, activity)
        Fit::Importer.new(import, user.id, file.path).call
      end

      points = Point.where(import_id: import.id)
      expect(points).to be_present
      expect(points.distinct.pluck(:tracker_id)).to eq(["import-#{import.id}"])
    end

    expect(user.points.distinct.pluck(:tracker_id).size).to eq(2)
  end
end
