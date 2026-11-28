# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Timezones::Lookup do
  def zone(tzid, min_lon, min_lat, max_lon, max_lat)
    Timezone.create!(
      tzid: tzid,
      geom: "SRID=4326;POLYGON((#{min_lon} #{min_lat}, #{max_lon} #{min_lat}, #{max_lon} #{max_lat}, " \
            "#{min_lon} #{max_lat}, #{min_lon} #{min_lat}))"
    )
  end

  context 'with loaded boundaries' do
    before do
      zone('America/Chicago', -100, 37, -94.6, 40)
      zone('America/Denver', -102.05, 37, -100, 40)
    end

    it 'returns the zone containing each coordinate, keyed like the input' do
      result = described_class.call(wichita: [-97.34, 37.69], goodland: [-101.71, 39.35])

      expect(result).to eq(wichita: 'America/Chicago', goodland: 'America/Denver')
    end

    it 'leaves coordinates outside every zone out of the result' do
      expect(described_class.call(berlin: [13.40, 52.52])).to eq({})
    end

    it 'skips keys without coordinates' do
      expect(described_class.call(none: nil, wichita: [-97.34, 37.69])).to eq(wichita: 'America/Chicago')
    end

    it 'answers a point on a shared border with the same zone every time' do
      expect(described_class.call(border: [-100, 38])).to eq(border: 'America/Chicago')
    end

    it 'does not query the database when no coordinate is given' do
      queries = []
      collector = ->(*, payload) { queries << payload[:sql] }

      result = ActiveSupport::Notifications.subscribed(collector, 'sql.active_record') do
        described_class.call(none: nil)
      end

      expect(result).to eq({})
      expect(queries).to be_empty
    end
  end

  it 'returns nothing when the boundaries are not loaded' do
    expect(described_class.call(wichita: [-97.34, 37.69])).to eq({})
  end

  it 'drops zone names the time zone database does not know' do
    zone('Mars/Olympus_Mons', -100, 37, -94.6, 40)

    expect(described_class.call(wichita: [-97.34, 37.69])).to eq({})
  end
end
