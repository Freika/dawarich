# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'TCX import robustness against repeated XML siblings' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }

  def import_file(path)
    Tcx::Importer.new(import, user.id, path).call
  end

  def fixture(name)
    Rails.root.join("spec/fixtures/files/tcx/#{name}").to_s
  end

  def write_tcx(trackpoints)
    file = Tempfile.new(['tcx', '.tcx'])
    file.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
        <Activities>
          <Activity Sport="Biking">
            <Lap StartTime="2021-04-09T18:30:30.000Z">
              <Track>#{trackpoints}</Track>
            </Lap>
          </Activity>
        </Activities>
      </TrainingCenterDatabase>
    XML
    file.close
    file.path
  end

  describe 'a Trackpoint with multiple Position siblings' do
    it 'keeps the first position instead of discarding the trackpoint' do
      expect { import_file(fixture('multiple_positions_per_trackpoint.tcx')) }.not_to raise_error

      expect(user.points.count).to eq(2)

      first, second = user.points.order(:timestamp).to_a
      expect(first.lat).to be_within(0.001).of(52.520)
      expect(first.lon).to be_within(0.001).of(13.405)
      expect(second.lat).to be_within(0.001).of(52.530)
      expect(second.lon).to be_within(0.001).of(13.410)
    end
  end

  describe 'a Trackpoint with multiple Extensions siblings' do
    let(:path) do
      write_tcx(<<~XML)
        <Trackpoint>
          <Time>2021-04-09T18:30:30.000Z</Time>
          <Position>
            <LatitudeDegrees>51.3402</LatitudeDegrees>
            <LongitudeDegrees>12.3712</LongitudeDegrees>
          </Position>
          <Extensions><TPX><Speed>1.5</Speed></TPX></Extensions>
          <Extensions><TPX><Speed>9.9</Speed></TPX></Extensions>
        </Trackpoint>
      XML
    end

    it 'imports the point and reads speed from the first Extensions' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
      expect(user.points.first.velocity.to_f).to eq(1.5)
    end
  end

  describe 'a Trackpoint with multiple Time siblings' do
    let(:path) do
      write_tcx(<<~XML)
        <Trackpoint>
          <Time>2021-04-09T18:30:30.000Z</Time>
          <Time>2021-04-09T18:30:31.000Z</Time>
          <Position>
            <LatitudeDegrees>51.3402</LatitudeDegrees>
            <LongitudeDegrees>12.3712</LongitudeDegrees>
          </Position>
        </Trackpoint>
      XML
    end

    it 'imports the point using the first timestamp' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
      expect(user.points.first.timestamp).to eq(Time.zone.parse('2021-04-09T18:30:30.000Z').to_i)
    end
  end

  describe 'a Trackpoint with multiple AltitudeMeters and coordinate siblings' do
    let(:path) do
      write_tcx(<<~XML)
        <Trackpoint>
          <Time>2021-04-09T18:30:30.000Z</Time>
          <AltitudeMeters>120.0</AltitudeMeters>
          <AltitudeMeters>999.0</AltitudeMeters>
          <Position>
            <LatitudeDegrees>51.3402</LatitudeDegrees>
            <LatitudeDegrees>41.1111</LatitudeDegrees>
            <LongitudeDegrees>12.3712</LongitudeDegrees>
          </Position>
        </Trackpoint>
      XML
    end

    it 'imports the point using the first altitude and coordinates' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
      point = user.points.first
      expect(point.lat).to be_within(0.001).of(51.3402)
      expect(point.altitude).to eq(120)
    end
  end

  describe 'a Trackpoint that is not a Hash' do
    let(:path) { write_tcx('<Trackpoint></Trackpoint>') }

    it 'skips it without raising' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(0)
    end
  end

  describe 'a self-closed Lap sibling' do
    let(:path) do
      file = Tempfile.new(['tcx', '.tcx'])
      file.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="Biking">
              <Lap StartTime="2021-04-09T18:30:30.000Z"><Track>
                <Trackpoint>
                  <Time>2021-04-09T18:30:30.000Z</Time>
                  <Position>
                    <LatitudeDegrees>51.3402</LatitudeDegrees>
                    <LongitudeDegrees>12.3712</LongitudeDegrees>
                  </Position>
                </Trackpoint>
              </Track></Lap>
              <Lap/>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
      XML
      file.close
      file.path
    end

    it 'skips the empty lap and imports the rest' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
    end
  end

  describe 'a self-closed Track sibling' do
    let(:path) do
      file = Tempfile.new(['tcx', '.tcx'])
      file.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="Biking">
              <Lap StartTime="2021-04-09T18:30:30.000Z">
                <Track>
                  <Trackpoint>
                    <Time>2021-04-09T18:30:30.000Z</Time>
                    <Position>
                      <LatitudeDegrees>51.3402</LatitudeDegrees>
                      <LongitudeDegrees>12.3712</LongitudeDegrees>
                    </Position>
                  </Trackpoint>
                </Track>
                <Track/>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
      XML
      file.close
      file.path
    end

    it 'skips the empty track and imports the rest' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
    end
  end

  describe 'a self-closed Position' do
    let(:path) do
      write_tcx(<<~XML)
        <Trackpoint><Time>2021-04-09T18:30:30.000Z</Time><Position/></Trackpoint>
        <Trackpoint>
          <Time>2021-04-09T18:31:00.000Z</Time>
          <Position>
            <LatitudeDegrees>51.3402</LatitudeDegrees>
            <LongitudeDegrees>12.3712</LongitudeDegrees>
          </Position>
        </Trackpoint>
      XML
    end

    it 'skips the positionless trackpoint and imports the rest' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(1)
    end
  end

  describe 'a Lap with multiple Track siblings' do
    let(:path) do
      file = Tempfile.new(['tcx', '.tcx'])
      file.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="Biking">
              <Lap StartTime="2021-04-09T18:30:30.000Z">
                <Track>
                  <Trackpoint>
                    <Time>2021-04-09T18:30:30.000Z</Time>
                    <Position>
                      <LatitudeDegrees>51.3402</LatitudeDegrees>
                      <LongitudeDegrees>12.3712</LongitudeDegrees>
                    </Position>
                  </Trackpoint>
                </Track>
                <Track>
                  <Trackpoint>
                    <Time>2021-04-09T18:45:00.000Z</Time>
                    <Position>
                      <LatitudeDegrees>51.3500</LatitudeDegrees>
                      <LongitudeDegrees>12.3800</LongitudeDegrees>
                    </Position>
                  </Trackpoint>
                </Track>
              </Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
      XML
      file.close
      file.path
    end

    it 'imports points from every track segment' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(2)
      expect(user.points.order(:timestamp).last.lat).to be_within(0.001).of(51.3500)
    end
  end

  describe 'a document with multiple Activities containers' do
    let(:path) do
      file = Tempfile.new(['tcx', '.tcx'])
      file.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities>
            <Activity Sport="Biking">
              <Lap StartTime="2021-04-09T18:30:30.000Z"><Track>
                <Trackpoint>
                  <Time>2021-04-09T18:30:30.000Z</Time>
                  <Position>
                    <LatitudeDegrees>51.3402</LatitudeDegrees>
                    <LongitudeDegrees>12.3712</LongitudeDegrees>
                  </Position>
                </Trackpoint>
              </Track></Lap>
            </Activity>
          </Activities>
          <Activities>
            <Activity Sport="Running">
              <Lap StartTime="2021-04-09T19:30:30.000Z"><Track>
                <Trackpoint>
                  <Time>2021-04-09T19:30:30.000Z</Time>
                  <Position>
                    <LatitudeDegrees>51.3500</LatitudeDegrees>
                    <LongitudeDegrees>12.3800</LongitudeDegrees>
                  </Position>
                </Trackpoint>
              </Track></Lap>
            </Activity>
          </Activities>
        </TrainingCenterDatabase>
      XML
      file.close
      file.path
    end

    it 'imports points from every container instead of raising' do
      expect { import_file(path) }.not_to raise_error

      expect(user.points.count).to eq(2)
      expect(user.points.order(:timestamp).last.lat).to be_within(0.001).of(51.3500)
    end
  end
end
