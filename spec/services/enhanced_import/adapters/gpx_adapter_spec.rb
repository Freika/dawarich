# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EnhancedImport::Adapters::GpxAdapter do
  let(:user) { create(:user) }

  def extract(body)
    import = create(:import, user: user, source: :gpx, name: "favourites-#{SecureRandom.hex(4)}.gpx")
    import.file.attach(io: StringIO.new(body), filename: 'favourites.gpx', content_type: 'application/gpx+xml')
    described_class.new(import).translate.to_a
  end

  def waypoint(color)
    <<~GPX
      <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
      <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
        <wpt lat="51.3402000" lon="12.3712000">
          <name>Cafe Riquet</name>
          <type>Food</type>
          <color>#{color}</color>
        </wpt>
      </gpx>
    GPX
  end

  describe 'colour normalisation' do
    it 'expands a three-digit hex colour' do
      expect(extract(waypoint('#0fc')).first.tag_color).to eq('#00ffcc')
    end

    it 'keeps a six-digit hex colour' do
      expect(extract(waypoint('#10c0f0')).first.tag_color).to eq('#10c0f0')
    end

    it 'drops the leading alpha byte of an eight-digit OsmAnd colour' do
      expect(extract(waypoint('#ffeecc22')).first.tag_color).to eq('#eecc22')
    end

    it 'yields no colour for a value it cannot read' do
      expect(extract(waypoint('chartreuse')).first.tag_color).to be_nil
    end

    it 'only ever yields a colour Tag accepts' do
      %w[#0fc #10c0f0 #ffeecc22].each do |value|
        color = extract(waypoint(value)).first.tag_color
        expect(build(:tag, user: user, color: color)).to be_valid, "rejected #{color.inspect} from #{value}"
      end
    end
  end

  describe 'nested children that are not the waypoint\'s own fields' do
    let(:with_link) do
      <<~GPX
        <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
        <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="51.3402000" lon="12.3712000">
            <name>Cafe Riquet</name>
            <link href="https://example.com"><text>Homepage</text><type>text/html</type></link>
            <extensions><osmand:color xmlns:osmand="https://osmand.net">#10c0f0</osmand:color></extensions>
          </wpt>
        </gpx>
      GPX
    end

    it 'does not take a link mime type as the waypoint category' do
      expect(extract(with_link).first.tag_name).to be_nil
    end

    it 'keeps the waypoint name rather than the link text' do
      expect(extract(with_link).first.name).to eq('Cafe Riquet')
    end

    it 'still reads a colour out of extensions' do
      expect(extract(with_link).first.tag_color).to eq('#10c0f0')
    end
  end

  describe 'identity' do
    it 'is stable for the same waypoint across parses' do
      first = extract(waypoint('#0fc')).first
      again = extract(waypoint('#10c0f0')).first

      expect(again.external_place_id).to eq(first.external_place_id)
    end

    it 'separates two waypoints that differ only by name' do
      first = extract(waypoint('#0fc')).first
      other = extract(waypoint('#0fc').sub('Cafe Riquet', 'Pharmacy')).first

      expect(other.external_place_id).not_to eq(first.external_place_id)
    end
  end

  describe 'coordinate validation' do
    def wpt(lat, lon, name = 'Cafe Riquet')
      <<~GPX
        <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
        <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="#{lat}" lon="#{lon}">
            <name>#{name}</name>
            <type>Food</type>
          </wpt>
        </gpx>
      GPX
    end

    it 'keeps a waypoint with real coordinates' do
      expect(extract(wpt('51.3402000', '12.3712000')).size).to eq(1)
    end

    it 'skips a waypoint whose coordinates are not numeric' do
      expect(extract(wpt('north', '12.3712000'))).to be_empty
    end

    it 'skips a Null Island waypoint' do
      expect(extract(wpt('0.0', '0.0'))).to be_empty
    end

    it 'still extracts the waypoints around an unreadable one' do
      body = wpt('north', '12.3712000').sub(
        '</gpx>',
        %(  <wpt lat="51.3402000" lon="12.3712000"><name>Pharmacy</name></wpt>\n</gpx>)
      )

      expect(extract(body).map(&:name)).to eq(['Pharmacy'])
    end
  end
end
