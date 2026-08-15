# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnTracks rec import with invalid UTF-8 bytes' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'owntracks.rec', source: :owntracks) }

  let(:rec_with_latin1_degree_sign) do
    json = %({"_type":"location","lat":48.1351,"lon":11.582,"tst":1716200000,"desc":"M\xB0nchen"})
    "2024-05-20T10:00:00Z\t*\t#{json}\n".dup.force_encoding(Encoding::BINARY)
  end

  def import_file
    file = Tempfile.new(['owntracks', '.rec'])
    file.binmode
    file.write(rec_with_latin1_degree_sign)
    file.close

    OwnTracks::Importer.new(import, user.id, file.path).call
  ensure
    file&.unlink
  end

  it 'imports without raising on invalid byte sequences' do
    expect { import_file }.not_to raise_error
  end

  it 'parses the coordinates' do
    import_file

    point = user.points.last
    expect(point).to be_present
    expect(point.lat).to be_within(0.0001).of(48.1351)
    expect(point.lon).to be_within(0.0001).of(11.582)
  end
end
