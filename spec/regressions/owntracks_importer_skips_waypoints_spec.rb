# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'OwnTracks .rec import is resilient to waypoint entries' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :owntracks) }

  it 'skips waypoint entries and imports only real location fixes without raising' do
    rec = [
      %(2024-03-01T09:03:09Z\t*\t{"_type":"location","lat":52.2,"lon":13.3,"tst":1709283789,"tid":"RO"}),
      %(2024-03-01T18:40:09Z\t*\t{"_type":"waypoint","desc":"Home","lat":52.23,"lon":13.33,"tst":1717459768})
    ].join("\n")

    file = Tempfile.new(['owntracks', '.rec'])
    file.write(rec)
    file.rewind

    expect do
      OwnTracks::Importer.new(import, user.id, file.path).call
    end.to change { import.points.count }.by(1)
  ensure
    file&.close
    file&.unlink
  end
end
