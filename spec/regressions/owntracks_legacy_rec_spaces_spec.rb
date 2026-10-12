# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OwnTracks legacy REC payload whitespace' do
  let(:payload) do
    { '_type' => 'location', 'lat' => 52.5, 'lon' => 13.4, 'tst' => 1_735_689_600,
      'SSID' => 'Home Wifi', 'topic' => 'owntracks/test/iPhone 12 Pro', 'inregions' => ['Home Office'] }
  end

  [' ', '   ', "\t"].each do |separator|
    it "preserves JSON strings and formatting with #{separator.inspect} columns" do
      line = ['2025-01-01T00:00:00Z', '*', JSON.generate(payload)].join(separator)

      expect(OwnTracks::RecParser.new(line).call).to eq([payload])
    end
  end

  it 'imports a legacy record containing spaces without dropping the file' do
    user = create(:user)
    import = create(:import, user: user, name: 'legacy.rec', skip_background_processing: true)
    line = "2025-01-01T00:00:00Z * #{JSON.generate(payload)}\n"
    import.file.attach(io: StringIO.new(line), filename: 'legacy.rec', content_type: 'text/plain')

    OwnTracks::Importer.new(import, user.id).call

    point = import.points.sole
    expect(point.ssid).to eq('Home Wifi')
    expect(point.topic).to eq('owntracks/test/iPhone 12 Pro')
    expect(point.timestamp).to eq(1_735_689_600)
  end
end
