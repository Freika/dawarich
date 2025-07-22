require 'benchmark'

# Test the optimized stats calculation
data = Benchmark.measure do
  user_id = 7

  last_calculated_at = DateTime.new(1970, 1, 1)

  time_diff = last_calculated_at.to_i..Time.current.to_i
  timestamps = Point.where(user_id:, timestamp: time_diff).pluck(:timestamp).uniq

  months = timestamps.group_by do |timestamp|
    time = Time.zone.at(timestamp)
    [time.year, time.month]
  end.keys

  months.each do |year, month|
    Stats::CalculateMonth.new(user_id, year, month).call
  end
end

puts "Stats calculation benchmark:"
puts "User Time: #{data.utime}s"
puts "System Time: #{data.stime}s"
puts "Total Time: #{data.real}s"

# @real=28.869485000148416,
# @stime=2.4980050000000027,
# @total=20.303141999999976,
# @utime=17.805136999999974>
