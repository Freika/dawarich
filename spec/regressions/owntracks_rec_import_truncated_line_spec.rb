# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'OwnTracks .rec import is resilient to a single malformed line' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user:, name: 'owntracks.rec', source: :owntracks) }

  let(:rec_with_truncated_middle_line) do
    [
      %(2024-03-01T09:03:09Z\t*\t{"_type":"location","lat":52.2,"lon":13.3,"tst":1709283789,"tid":"RO"}),
      %(2024-03-01T17:46:02Z\t*\t{truncated-because-download-was-interrupted),
      %(2024-03-01T18:00:00Z\t*\t{"_type":"location","lat":52.3,"lon":13.4,"tst":1709315162,"tid":"RO"})
    ].join("\n") << "\n"
  end

  def import_file
    file = Tempfile.new(['owntracks', '.rec'])
    file.write(rec_with_truncated_middle_line)
    file.rewind

    OwnTracks::Importer.new(import, user.id, file.path).call
  ensure
    file&.close
    file&.unlink
  end

  it 'skips the malformed line and imports the surrounding valid records without raising' do
    expect { import_file }.to change { import.points.count }.by(2)
  end

  it 'preserves the coordinates of the records on either side of the truncated line' do
    import_file

    expect(user.points.order(:timestamp).map(&:lat)).to contain_exactly(52.2, 52.3)
  end
end
