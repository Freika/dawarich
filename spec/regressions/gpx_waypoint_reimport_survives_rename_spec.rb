# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Re-importing a favourite that was renamed does not duplicate it' do
  let(:user) { create(:user) }

  def import_gpx(body, label)
    filename = "#{label}.gpx"
    import = create(:import, user: user, source: :gpx, name: filename)
    import.file.attach(io: StringIO.new(body), filename: filename, content_type: 'application/gpx+xml')
    EnhancedImport::ExtractJob.new.perform(import.id)
    import
  end

  def favourite(name)
    <<~GPX
      <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
      <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
        <wpt lat="51.3402000" lon="12.3712000">
          <name>#{name}</name>
          <type>Food</type>
        </wpt>
      </gpx>
    GPX
  end

  it 'keeps a single place when the waypoint is renamed between imports' do
    import_gpx(favourite('Cafe Riquet'), 'first')
    expect(Place.where(user_id: user.id).count).to eq(1)

    import_gpx(favourite('Riquet Kaffeehaus'), 'second')

    expect(Place.where(user_id: user.id).count).to eq(1)
  end

  it 'keeps two differently named favourites that sit on the same spot apart' do
    body = <<~GPX
      <?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
      <gpx version="1.1" creator="OsmAnd~" xmlns="http://www.topografix.com/GPX/1/1">
        <wpt lat="51.3402000" lon="12.3712000"><name>Doctor</name><type>Health</type></wpt>
        <wpt lat="51.3402000" lon="12.3712000"><name>Pharmacy</name><type>Health</type></wpt>
      </gpx>
    GPX

    import_gpx(body, 'first')

    expect(Place.where(user_id: user.id).pluck(:name)).to contain_exactly('Doctor', 'Pharmacy')
  end

  it 'carries the new name onto the place when a favourite is renamed' do
    import_gpx(favourite('Cafe Riquet'), 'first')
    import_gpx(favourite('Riquet Kaffeehaus'), 'second')

    expect(Place.where(user_id: user.id).pluck(:name)).to eq(['Riquet Kaffeehaus'])
  end

  it 'adds a new nearby favourite instead of renaming the one already there' do
    import_gpx(favourite('Cafe Riquet'), 'first')

    nearby = favourite('Bakery').sub('lon="12.3712000"', 'lon="12.3712500"')
    import_gpx(nearby, 'second')

    expect(Place.where(user_id: user.id).pluck(:name)).to contain_exactly('Cafe Riquet', 'Bakery')
  end

  it 'still separates two favourites that share a name at different places' do
    import_gpx(favourite('Home'), 'first')

    elsewhere = favourite('Home').sub('lat="51.3402000" lon="12.3712000"', 'lat="52.5200000" lon="13.4050000"')
    import_gpx(elsewhere, 'second')

    expect(Place.where(user_id: user.id).count).to eq(2)
  end
end
