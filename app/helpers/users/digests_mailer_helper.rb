# frozen_string_literal: true

module Users::DigestsMailerHelper
  BLOCKS         = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇ █].freeze
  HEATMAP_LEVELS = %w[· ░ ▒ ▓ █].freeze

  # Horizontal bar chart.
  #   values:  numeric array
  #   labels:  same-length string array
  #   width:   max bar width in characters
  #   suffix:  units printed after the numeric value
  # Produces lines like:  "A    ██████████  50 km"
  def ascii_hbar(values, labels:, width: 24, suffix: '')
    return '' if values.empty?

    max = values.map(&:to_f).max
    max = 1.0 if max.zero?
    label_width = labels.map(&:to_s).map(&:length).max || 0

    values.zip(labels).map do |value, label|
      fill = ((value.to_f / max) * width).round
      bar  = '█' * fill
      "#{label.to_s.ljust(label_width)}  #{bar.ljust(width)}  #{value}#{suffix}"
    end.join("\n")
  end

  # Single-line sparkline built from BLOCKS.
  # All-equal values render as full-height blocks; empty array → "".
  def ascii_sparkline(values)
    return '' if values.empty?

    max = values.map(&:to_f).max
    min = values.map(&:to_f).min
    range = (max - min).to_f
    return BLOCKS.last * values.size if range.zero?

    values.map do |v|
      idx = (((v.to_f - min) / range) * (BLOCKS.size - 1)).round
      BLOCKS[idx]
    end.join
  end

  # 7-row × ~52-column grid of HEATMAP_LEVELS characters.
  # Rows are Monday..Sunday. Columns are consecutive calendar weeks starting
  # from the Monday of the week containing start_date.
  # Level is chosen by quartile of non-zero daily distances:
  #   0      → ·
  #   < Q1   → ░
  #   < Q2   → ▒
  #   < Q3   → ▓
  #   ≥ Q3   → █   (ties go to the higher bucket so peak days render full)
  def ascii_year_heatmap(daily_values, start_date:)
    non_zero = daily_values.values.select { |v| v.to_f.positive? }.sort
    thresholds =
      if non_zero.empty?
        [0, 0, 0]
      else
        [non_zero[non_zero.size / 4], non_zero[non_zero.size / 2], non_zero[non_zero.size * 3 / 4]]
      end

    grid_start = start_date - ((start_date.wday.zero? ? 7 : start_date.wday) - 1)
    end_date   = daily_values.keys.max || start_date
    weeks      = ((end_date - grid_start).to_i / 7) + 1

    rows = (0..6).map { (0...weeks).map { |_| ' ' } }

    (0...(weeks * 7)).each do |offset|
      date = grid_start + offset
      next if date > end_date

      value = daily_values[date].to_f
      level =
        if value.zero?               then HEATMAP_LEVELS[0]
        elsif value < thresholds[0]  then HEATMAP_LEVELS[1]
        elsif value < thresholds[1]  then HEATMAP_LEVELS[2]
        elsif value < thresholds[2]  then HEATMAP_LEVELS[3]
        else                              HEATMAP_LEVELS[4]
        end

      week = offset / 7
      weekday = offset % 7
      rows[weekday][week] = level
    end

    rows.map(&:join).join("\n")
  end

  def ascii_trend(current, previous)
    current  = current.to_f
    previous = previous.to_f

    return '→ same' if current == previous
    return '↑ new' if previous.zero?

    delta = ((current - previous) / previous * 100).round
    sign  = delta.positive? ? '+' : ''
    arrow = delta.positive? ? '↑' : '↓'
    "#{arrow} #{sign}#{delta}%"
  end

  # Render a trend when only the percent-change is stored (e.g. month_over_month['distance_change_percent']).
  # Guards against percent == -100 which would make 1 + pct/100 == 0 → Infinity → NaN → FloatDomainError.
  def ascii_trend_from_pct(current, percent_change)
    return '→ same' if percent_change.nil?

    denom = 1 + percent_change.to_f / 100.0
    return current.to_f.positive? ? '↑ new' : '→ same' if denom.zero?

    ascii_trend(current, current.to_f / denom)
  end

  def ascii_ranked_list(items, value_key:, label_key:, width: 20, format: ->(v) { v })
    return '' if items.empty?

    sorted = items.sort_by { |item| -item[value_key].to_f }
    max    = sorted.first[value_key].to_f
    max    = 1.0 if max.zero?
    label_width = sorted.map { |item| item[label_key].to_s.length }.max || 0

    sorted.each_with_index.map do |item, index|
      value = item[value_key]
      fill  = ((value.to_f / max) * width).round
      bar   = '█' * fill
      "#{index + 1}. #{item[label_key].to_s.ljust(label_width)}  #{bar.ljust(width)}  #{format.call(value)}"
    end.join("\n")
  end
end
