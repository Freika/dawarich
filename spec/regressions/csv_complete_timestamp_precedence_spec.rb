# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'CSV complete timestamp precedence' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, source: :csv) }

  around { |example| Time.use_zone('UTC') { example.run } }

  def import_csv(headers, row)
    Tempfile.create(['csv-timestamp-', '.csv']) do |file|
      file.write(CSV.generate_line(headers))
      file.write(CSV.generate_line(row))
      file.flush
      Csv::Importer.new(import, user.id, file.path).call
    end
  end

  %w[timestamp datetime when created_at recorded_at fixTime tst].each do |header|
    context "with a #{header} column and separate DATE/TIME columns" do
      it 'preserves the complete timestamp and its UTC offset' do
        import_csv(['lat', 'lon', 'DATE', 'TIME', header],
                   ['51', '1', '2021-01-01', '03:00:00', '2020-01-01T03:00:00+02:00'])

        expect(import.points.pluck(:timestamp)).to eq([Time.iso8601('2020-01-01T01:00:00Z').to_i])
        expect(import.reload.raw_data['skipped_rows']).to eq(0)
      end
    end
  end

  [['', '03:00:00'], ['2020-01-01', ''], ['', '']].each do |date, time|
    it "retains a complete timestamp when DATE=#{date.inspect} and TIME=#{time.inspect}" do
      import_csv(%w[lat lon timestamp DATE TIME], ['51', '1', '2020-01-01T01:02:03Z', date, time])

      expect(import.points.pluck(:timestamp)).to eq([1_577_840_523])
      expect(import.reload.raw_data['skipped_rows']).to eq(0)
    end
  end

  %w[1577840523 1577840523000].each do |timestamp|
    it "preserves the Unix timestamp #{timestamp}" do
      import_csv(%w[lat lon timestamp DATE TIME], ['51', '1', timestamp, '2021-01-01', '01:02:03'])

      expect(import.points.pluck(:timestamp)).to eq([1_577_840_523])
    end
  end

  %w[2020-01-01T03:00:00+02:00 1577840400 1577840400000].each do |timestamp|
    ['', '2024-01-01'].each do |date|
      it "preserves a complete TIME=#{timestamp} with DATE=#{date.inspect}" do
        import_csv(%w[lat lon DATE TIME], ['51', '1', date, timestamp])

        expect(import.points.pluck(:timestamp)).to eq([1_577_840_400])
        expect(import.reload.raw_data['skipped_rows']).to eq(0)
      end
    end
  end

  it 'combines reordered, mixed-case date and time columns without a complete timestamp' do
    import_csv([' Time ', 'lon', ' daTE ', 'lat'], ['01:21:52', '1', '2008/12/02', '51'])

    expect(import.points.pluck(:timestamp)).to eq([Time.iso8601('2008-12-02T01:21:52Z').to_i])
    expect(import.reload.raw_data['skipped_rows']).to eq(0)
  end
end
