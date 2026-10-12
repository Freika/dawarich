# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tcx::Importer do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :tcx) }

  describe '#call' do
    context 'with running activity TCX' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/tcx/running.tcx').to_s }

      before { described_class.new(import, user.id, file_path).call }

      it 'creates points only for trackpoints with GPS' do
        expect(user.points.count).to eq(1)
      end

      it 'parses coordinates correctly' do
        point = user.points.order(:timestamp).first
        expect(point.lat).to be_within(0.001).of(52.520)
        expect(point.lon).to be_within(0.001).of(13.405)
      end

      it 'parses timestamps' do
        point = user.points.order(:timestamp).first
        expect(point.timestamp).to eq(Time.zone.parse('2024-01-01T10:00:00Z').to_i)
      end

      it 'does not persist raw_data for imported points' do
        expect(Point.where(import_id: import.id).pluck(:raw_data).uniq).to eq([{}])
      end

      it 'stores the mapped activity type in motion_data' do
        expect(Point.where(import_id: import.id).pluck(:motion_data).uniq)
          .to eq([{ 'activity_type' => 'running' }])
      end
    end

    context 'with no-GPS TCX (indoor)' do
      let(:file_path) { Rails.root.join('spec/fixtures/files/tcx/no_gps.tcx').to_s }

      it 'creates zero points' do
        described_class.new(import, user.id, file_path).call
        expect(user.points.count).to eq(0)
      end
    end

    context 'with problematic XML content' do
      let(:file) { Tempfile.new(['problematic', '.tcx']) }
      let(:file_path) { file.path }

      before do
        file.write(tcx_content)
        file.close
      end

      after do
        file.unlink
      end

      context 'with raw ampersands in text fields' do
        let(:tcx_content) { build_tcx(id: 'Passion & Punishment') }

        it 'imports GPS trackpoints' do
          expect { described_class.new(import, user.id, file_path).call }
            .to change { user.points.count }.by(1)
        end
      end

      context 'with CDATA sections containing ampersands' do
        let(:tcx_content) { build_tcx(notes: '<![CDATA[Tom & Jerry]]>') }

        it 'imports GPS trackpoints' do
          expect { described_class.new(import, user.id, file_path).call }
            .to change { user.points.count }.by(1)
        end
      end

      context 'with valid XML entities' do
        let(:tcx_content) { build_tcx(notes: 'Fish &amp; Chips &#38; Salt &#x26; Vinegar') }

        it 'imports GPS trackpoints' do
          expect { described_class.new(import, user.id, file_path).call }
            .to change { user.points.count }.by(1)
        end
      end

      context 'with undefined named entities' do
        let(:tcx_content) { build_tcx(notes: 'a&nbsp;b &copy; c') }

        it 'imports GPS trackpoints' do
          expect { described_class.new(import, user.id, file_path).call }
            .to change { user.points.count }.by(1)
        end
      end

      context 'with numeric references to XML-illegal characters' do
        let(:tcx_content) { build_tcx(notes: 'beep &#2; boop') }

        it 'imports GPS trackpoints' do
          expect { described_class.new(import, user.id, file_path).call }
            .to change { user.points.count }.by(1)
        end
      end
    end
  end

  def build_tcx(id: 'Morning Run', notes: nil)
    notes_xml = notes ? "<Extensions><TPX><Notes>#{notes}</Notes></TPX></Extensions>" : ''

    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <TrainingCenterDatabase>
        <Activities>
          <Activity Sport="Running">
            <Id>#{id}</Id>
            <Lap StartTime="2024-01-01T10:00:00Z">
              <Track>
                <Trackpoint>
                  <Time>2024-01-01T10:00:00Z</Time>
                  <Position>
                    <LatitudeDegrees>52.520</LatitudeDegrees>
                    <LongitudeDegrees>13.405</LongitudeDegrees>
                  </Position>
                  #{notes_xml}
                </Trackpoint>
              </Track>
            </Lap>
          </Activity>
        </Activities>
      </TrainingCenterDatabase>
    XML
  end
end
