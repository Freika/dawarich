# frozen_string_literal: true

module InsightsChartsHelper
  RACE_FRAME = { width: 720, height: 240, left: 46, right: 12, top: 12, bottom: 26 }.freeze

  RaceChart = Data.define(:frame, :current, :previous, :current_path, :area_path, :previous_path, :ticks,
                          :months, :today_x, :today_current_y, :today_previous_y)

  def distance_race_chart(race, unit)
    current = race.current.map { Stat.convert_distance(_1, unit).round(1) }
    previous = race.previous&.map { Stat.convert_distance(_1, unit).round(1) }
    top = nice_ceiling([current.last, previous&.last].compact.max)
    days = Date.new(race.year, 12, 31).yday
    f = RACE_FRAME

    x = ->(index) { (f[:left] + (index.to_f / (days - 1)) * (f[:width] - f[:left] - f[:right])).round(1) }
    y = ->(value) { (f[:top] + (1 - (value / top)) * (f[:height] - f[:top] - f[:bottom])).round(1) }
    line = ->(values) { values.each_with_index.map { |v, i| "#{i.zero? ? 'M' : 'L'}#{x.call(i)},#{y.call(v)}" }.join }
    last = current.size - 1

    RaceChart.new(
      frame: f, current:, previous:,
      current_path: line.call(current),
      area_path: "#{line.call(current)}L#{x.call(last)},#{y.call(0)}L#{x.call(0)},#{y.call(0)}Z",
      previous_path: previous && line.call(previous),
      ticks: [0, 0.25, 0.5, 0.75, 1].map { [compact_distance(top * _1), y.call(top * _1)] },
      months: (1..12).map do |m|
        [l(Date.new(race.year, m, 1), format: '%b'), x.call(Date.new(race.year, m, 1).yday - 1)]
      end,
      today_x: x.call(last),
      today_current_y: y.call(current.last),
      today_previous_y: previous && y.call(previous[[last, previous.size - 1].min])
    )
  end

  COUNTRY_COLORS = %w[
    #2563eb #c2410c #059669 #c026d3 #b45309 #0e7490 #e11d48 #8b5cf6
    #4d7c0f #db2777 #0d9488 #a16207 #6366f1 #dc2626
  ].freeze
  CALENDAR_ALPHA = { 1 => 0.32, 2 => 0.5, 3 => 0.72, 4 => 1 }.freeze
  RIBBON_LANES = 8

  def country_colors(countries)
    countries.each_with_index.to_h do |country, index|
      [country[:country_name], COUNTRY_COLORS[index % COUNTRY_COLORS.size]]
    end
  end

  def calendar_alpha(meters, levels)
    CALENDAR_ALPHA.fetch(calculate_activity_level(meters, levels), 0)
  end

  def ribbon_segment(period, year)
    days_in_year = Date.new(year, 12, 31).yday.to_f
    start_date = Date.parse(period[:start_date])
    {
      left: ((start_date.yday - 1) / days_in_year * 100).round(3),
      width: [period[:consecutive_days] / days_in_year * 100, 0.4].max.round(3),
      start_date:, end_date: Date.parse(period[:end_date]), days: period[:consecutive_days]
    }
  end

  private

  def nice_ceiling(value)
    return 1 unless value&.positive?

    magnitude = 10**Math.log10(value).floor
    step = [1, 2, 2.5, 5, 10].find { value <= _1 * magnitude }
    step * magnitude
  end

  def compact_distance(value)
    value >= 1000 ? "#{(value / 1000.0).round(1).to_s.delete_suffix('.0')}k" : value.round.to_s
  end
end
