# frozen_string_literal: true

require_relative 'optimized_tracks_v1'
require_relative 'optimized_tracks_v2'

# Benchmark script to compare three different track generation approaches:
# - Original: Individual distance queries (current implementation)
# - V1: LAG-based distance pre-calculation with Ruby segmentation  
# - V2: Full SQL segmentation with PostgreSQL window functions
#
# Usage:
#   rails runner lib/tracks_optimization_benchmark.rb USER_ID START_DATE END_DATE

class TracksOptimizationBenchmark
  attr_reader :user, :start_date, :end_date, :start_timestamp, :end_timestamp

  def initialize(user_id, start_date, end_date)
    @user = User.find(user_id)
    @start_date = Date.parse(start_date)
    @end_date = Date.parse(end_date)
    @start_timestamp = @start_date.beginning_of_day.to_i
    @end_timestamp = @end_date.end_of_day.to_i

    puts "🔬 Track Generation Optimization Benchmark"
    puts "👤 User: #{user.email} (ID: #{user.id})"
    puts "📅 Timeframe: #{start_date} to #{end_date}"
    
    check_data_availability
  end

  def run_all_benchmarks
    results = {}

    puts "\n" + "=" * 80
    puts "🏃 RUNNING ALL BENCHMARKS"
    puts "=" * 80

    # Test Original approach
    puts "\n1️⃣  Testing ORIGINAL approach..."
    results[:original] = benchmark_original

    # Test V1 approach  
    puts "\n2️⃣  Testing V1 (LAG + Ruby) approach..."
    results[:v1] = benchmark_v1

    # Test V2 approach
    puts "\n3️⃣  Testing V2 (Full SQL) approach..."
    results[:v2] = benchmark_v2

    # Compare results
    puts "\n" + "=" * 80
    puts "📊 PERFORMANCE COMPARISON"
    puts "=" * 80
    compare_results(results)

    # Save results to files
    save_results_to_files(results)

    results
  end

  private

  def check_data_availability
    point_count = user.tracked_points.where(timestamp: start_timestamp..end_timestamp).count
    existing_tracks = user.tracks.where(start_at: Time.zone.at(start_timestamp)..Time.zone.at(end_timestamp)).count

    puts "📊 Dataset: #{point_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} points"
    puts "🛤️  Existing tracks: #{existing_tracks}"

    if point_count == 0
      puts "❌ No points found in timeframe"
      exit 1
    end

    if point_count > 50000
      puts "⚠️  Large dataset detected. This benchmark may take a while..."
    end
  end

  def benchmark_original
    puts "   Using standard Tracks::Generator..."
    
    # Clean existing tracks
    cleanup_tracks
    
    # Monitor performance
    memory_start = get_memory_mb
    query_monitor = QueryMonitor.new
    query_monitor.start
    
    start_time = Time.current
    
    begin
      generator = Tracks::Generator.new(
        user,
        start_at: Time.zone.at(start_timestamp),
        end_at: Time.zone.at(end_timestamp),
        mode: :bulk
      )
      tracks_created = generator.call
      success = true
    rescue => e
      success = false
      error = e.message
      tracks_created = 0
    end
    
    end_time = Time.current
    memory_end = get_memory_mb
    query_monitor.stop
    
    execution_time = end_time - start_time
    
    result = {
      approach: "Original",
      success: success,
      error: error,
      execution_time: execution_time,
      tracks_created: tracks_created,
      memory_increase: memory_end - memory_start,
      query_count: query_monitor.query_count,
      query_time_ms: query_monitor.total_time_ms
    }
    
    print_result(result)
    result
  end

  def benchmark_v1
    puts "   Using V1: LAG + Ruby segmentation..."
    
    # Clean existing tracks
    cleanup_tracks
    
    # For V1, we need to modify the existing generator to use our optimized methods
    # This is a simplified test - in practice we'd modify the actual generator
    
    memory_start = get_memory_mb
    query_monitor = QueryMonitor.new  
    query_monitor.start
    
    start_time = Time.current
    
    begin
      # Load points
      points = user.tracked_points
                  .where(timestamp: start_timestamp..end_timestamp)
                  .order(:timestamp)
      
      # V1: Use optimized segmentation with pre-calculated distances
      if points.size > 1
        distance_data = Point.calculate_all_consecutive_distances(points)
      else
        distance_data = {}
      end
      
      # Segment using V1 approach (simplified for benchmark)
      segments = split_points_with_precalculated_distances(points, distance_data)
      
      tracks_created = 0
      segments.each do |segment|
        if segment.size >= 2
          track = create_track_v1(segment)
          tracks_created += 1 if track
        end
      end
      
      success = true
    rescue => e
      success = false
      error = e.message  
      tracks_created = 0
    end
    
    end_time = Time.current
    memory_end = get_memory_mb
    query_monitor.stop
    
    execution_time = end_time - start_time
    
    result = {
      approach: "V1 (LAG + Ruby)",
      success: success,
      error: error,
      execution_time: execution_time,
      tracks_created: tracks_created,
      memory_increase: memory_end - memory_start,
      query_count: query_monitor.query_count,
      query_time_ms: query_monitor.total_time_ms
    }
    
    print_result(result)
    result
  end

  def benchmark_v2
    puts "   Using V2: Full SQL segmentation..."
    
    cleanup_tracks
    
    memory_start = get_memory_mb
    query_monitor = QueryMonitor.new
    query_monitor.start
    
    start_time = Time.current
    
    begin
      generator = OptimizedTracksGeneratorV2.new(
        user,
        start_at: Time.zone.at(start_timestamp),
        end_at: Time.zone.at(end_timestamp),
        mode: :bulk
      )
      tracks_created = generator.call
      success = true
    rescue => e
      success = false
      error = e.message
      tracks_created = 0
    end
    
    end_time = Time.current
    memory_end = get_memory_mb
    query_monitor.stop
    
    execution_time = end_time - start_time
    
    result = {
      approach: "V2 (Full SQL)",
      success: success,
      error: error,
      execution_time: execution_time,
      tracks_created: tracks_created,
      memory_increase: memory_end - memory_start,
      query_count: query_monitor.query_count,
      query_time_ms: query_monitor.total_time_ms
    }
    
    print_result(result)
    result
  end

  def split_points_with_precalculated_distances(points, distance_data)
    return [] if points.empty?

    segments = []
    current_segment = []

    points.each do |point|
      if current_segment.empty?
        current_segment = [point]
      elsif should_break_segment_v1?(point, current_segment.last, distance_data)
        segments << current_segment if current_segment.size >= 2
        current_segment = [point]
      else
        current_segment << point
      end
    end

    segments << current_segment if current_segment.size >= 2
    segments
  end

  def should_break_segment_v1?(current_point, previous_point, distance_data)
    return false if previous_point.nil?

    point_data = distance_data[current_point.id]
    return false unless point_data

    time_threshold_seconds = user.safe_settings.minutes_between_routes.to_i * 60
    distance_threshold_meters = user.safe_settings.meters_between_routes.to_i

    return true if point_data[:time_diff_seconds] > time_threshold_seconds
    return true if point_data[:distance_meters] > distance_threshold_meters

    false
  end

  def create_track_v1(points)
    return nil if points.size < 2

    track = Track.new(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    # Use LAG-based distance calculation
    track.distance = Point.total_distance_lag(points, :m).round
    track.duration = points.last.timestamp - points.first.timestamp
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Elevation stats (same as original)
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max = elevation_stats[:max]
    track.elevation_min = elevation_stats[:min]

    if track.save
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
      track
    else
      nil
    end
  end

  def cleanup_tracks
    user.tracks.where(start_at: Time.zone.at(start_timestamp)..Time.zone.at(end_timestamp)).destroy_all
  end

  def print_result(result)
    status = result[:success] ? "✅ SUCCESS" : "❌ FAILED"
    puts "   #{status}"
    puts "   ⏱️  Time: #{format_duration(result[:execution_time])}"
    puts "   🛤️  Tracks: #{result[:tracks_created]}"
    puts "   💾 Memory: +#{result[:memory_increase].round(1)}MB"
    puts "   🗄️  Queries: #{result[:query_count]} (#{result[:query_time_ms].round(1)}ms)"
    puts "   ❌ Error: #{result[:error]}" if result[:error]
  end

  def compare_results(results)
    return unless results[:original] && results[:v1] && results[:v2]

    puts sprintf("%-20s %-10s %-12s %-10s %-15s %-10s", 
                 "Approach", "Time", "Tracks", "Memory", "Queries", "Query Time")
    puts "-" * 80

    [:original, :v1, :v2].each do |approach|
      result = results[approach]
      next unless result[:success]
      
      puts sprintf("%-20s %-10s %-12s %-10s %-15s %-10s",
                   result[:approach],
                   format_duration(result[:execution_time]),
                   result[:tracks_created],
                   "+#{result[:memory_increase].round(1)}MB",
                   result[:query_count],
                   "#{result[:query_time_ms].round(1)}ms")
    end

    # Calculate improvements
    if results[:original][:success]
      original_time = results[:original][:execution_time]
      original_queries = results[:original][:query_count]

      puts "\n🚀 Performance Improvements vs Original:"
      
      if results[:v1][:success]
        v1_speedup = (original_time / results[:v1][:execution_time]).round(2)
        v1_query_reduction = ((original_queries - results[:v1][:query_count]) / original_queries.to_f * 100).round(1)
        puts "   V1: #{v1_speedup}x faster, #{v1_query_reduction}% fewer queries"
      end
      
      if results[:v2][:success]
        v2_speedup = (original_time / results[:v2][:execution_time]).round(2)
        v2_query_reduction = ((original_queries - results[:v2][:query_count]) / original_queries.to_f * 100).round(1)
        puts "   V2: #{v2_speedup}x faster, #{v2_query_reduction}% fewer queries"
      end
    end
  end

  def save_results_to_files(results)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    point_count = user.tracked_points.where(timestamp: start_timestamp..end_timestamp).count
    
    # Create detailed results structure
    benchmark_data = {
      meta: {
        timestamp: Time.current.iso8601,
        user_id: user.id,
        user_email: user.email,
        start_date: start_date.strftime('%Y-%m-%d'),
        end_date: end_date.strftime('%Y-%m-%d'),
        point_count: point_count,
        ruby_version: RUBY_VERSION,
        rails_version: Rails.version,
        database_adapter: ActiveRecord::Base.connection.adapter_name
      },
      results: results,
      performance_analysis: analyze_performance_data(results)
    }

    # Save JSON results for programmatic analysis
    json_filename = "tracks_optimization_#{timestamp}.json"
    json_path = Rails.root.join('lib', json_filename)
    File.write(json_path, JSON.pretty_generate(benchmark_data))

    # Save human-readable markdown report
    md_filename = "tracks_optimization_#{timestamp}.md"
    md_path = Rails.root.join('lib', md_filename)
    File.write(md_path, generate_markdown_report(benchmark_data))

    puts "\n💾 Results saved:"
    puts "   📄 JSON: #{json_path}"
    puts "   📝 Report: #{md_path}"
  end

  def analyze_performance_data(results)
    return {} unless results[:original] && results[:original][:success]

    original = results[:original]
    analysis = {
      baseline: {
        execution_time: original[:execution_time],
        query_count: original[:query_count],
        memory_usage: original[:memory_increase]
      }
    }

    [:v1, :v2].each do |version|
      next unless results[version] && results[version][:success]
      
      result = results[version]
      analysis[version] = {
        speedup_factor: (original[:execution_time] / result[:execution_time]).round(2),
        query_reduction_percent: ((original[:query_count] - result[:query_count]) / original[:query_count].to_f * 100).round(1),
        memory_change_percent: ((result[:memory_increase] - original[:memory_increase]) / original[:memory_increase].to_f * 100).round(1),
        execution_time_saved: (original[:execution_time] - result[:execution_time]).round(2)
      }
    end

    analysis
  end

  def generate_markdown_report(benchmark_data)
    meta = benchmark_data[:meta]
    results = benchmark_data[:results]
    analysis = benchmark_data[:performance_analysis]

    report = <<~MD
      # Tracks Generation Optimization Benchmark Report

      **Generated:** #{meta[:timestamp]}  
      **User:** #{meta[:user_email]} (ID: #{meta[:user_id]})  
      **Timeframe:** #{meta[:start_date]} to #{meta[:end_date]}  
      **Dataset:** #{meta[:point_count].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} points  
      **Environment:** Ruby #{meta[:ruby_version]}, Rails #{meta[:rails_version]}, #{meta[:database_adapter]}

      ## Summary

      This benchmark compares three approaches to track generation:
      - **Original:** Individual PostGIS queries for each distance calculation
      - **V1 (LAG + Ruby):** PostgreSQL LAG for batch distance calculation, Ruby segmentation
      - **V2 (Full SQL):** Complete segmentation using PostgreSQL window functions

      ## Results

      | Approach | Status | Time | Tracks | Memory | Queries | Query Time |
      |----------|--------|------|--------|--------|---------|------------|
    MD

    [:original, :v1, :v2].each do |approach|
      next unless results[approach]
      
      result = results[approach]
      status = result[:success] ? "✅" : "❌"
      
      report += "| #{result[:approach]} | #{status} | #{format_duration(result[:execution_time])} | #{result[:tracks_created]} | +#{result[:memory_increase].round(1)}MB | #{result[:query_count]} | #{result[:query_time_ms].round(1)}ms |\n"
    end

    if analysis[:v1] || analysis[:v2]
      report += "\n## Performance Improvements\n\n"
      
      if analysis[:v1]
        v1 = analysis[:v1]
        report += "### V1 (LAG + Ruby) vs Original\n"
        report += "- **#{v1[:speedup_factor]}x faster** execution\n"
        report += "- **#{v1[:query_reduction_percent]}% fewer** database queries\n"
        report += "- **#{format_duration(v1[:execution_time_saved])} time saved**\n"
        report += "- Memory change: #{v1[:memory_change_percent] > 0 ? '+' : ''}#{v1[:memory_change_percent]}%\n\n"
      end
      
      if analysis[:v2]
        v2 = analysis[:v2]
        report += "### V2 (Full SQL) vs Original\n"
        report += "- **#{v2[:speedup_factor]}x faster** execution\n"
        report += "- **#{v2[:query_reduction_percent]}% fewer** database queries\n"
        report += "- **#{format_duration(v2[:execution_time_saved])} time saved**\n"
        report += "- Memory change: #{v2[:memory_change_percent] > 0 ? '+' : ''}#{v2[:memory_change_percent]}%\n\n"
      end
    end

    # Add detailed results
    report += "## Detailed Results\n\n"
    
    [:original, :v1, :v2].each do |approach|
      next unless results[approach]
      
      result = results[approach]
      report += "### #{result[:approach]}\n\n"
      
      if result[:success]
        report += "- ✅ **Status:** Success\n"
        report += "- ⏱️ **Execution Time:** #{format_duration(result[:execution_time])}\n"
        report += "- 🛤️ **Tracks Created:** #{result[:tracks_created]}\n"
        report += "- 💾 **Memory Increase:** +#{result[:memory_increase].round(1)}MB\n"
        report += "- 🗄️ **Database Queries:** #{result[:query_count]}\n"
        report += "- ⚡ **Query Time:** #{result[:query_time_ms].round(1)}ms\n"
        
        if result[:query_count] > 0
          avg_query_time = (result[:query_time_ms] / result[:query_count]).round(2)
          report += "- 📊 **Average Query Time:** #{avg_query_time}ms\n"
        end
      else
        report += "- ❌ **Status:** Failed\n"
        report += "- 🚨 **Error:** #{result[:error]}\n"
      end
      
      report += "\n"
    end

    report += "## Recommendations\n\n"
    
    if analysis[:v2] && analysis[:v2][:speedup_factor] > analysis.dig(:v1, :speedup_factor).to_f
      report += "🚀 **V2 (Full SQL)** shows the best performance with #{analysis[:v2][:speedup_factor]}x speedup.\n\n"
      report += "Benefits:\n"
      report += "- Minimal database queries (#{results.dig(:v2, :query_count)} vs #{results.dig(:original, :query_count)})\n"
      report += "- Fastest execution time\n"
      report += "- Leverages PostgreSQL's optimized window functions\n\n"
    elsif analysis[:v1]
      report += "🏃 **V1 (LAG + Ruby)** provides good performance improvements with #{analysis[:v1][:speedup_factor]}x speedup.\n\n"
    end

    if results[:original] && results[:original][:query_count] > 50000
      report += "⚠️ **Current implementation** makes excessive database queries (#{results[:original][:query_count]}) for this dataset size.\n\n"
    end

    report += "---\n*Generated by TracksOptimizationBenchmark*"
    
    report
  end

  # Helper methods
  def get_memory_mb
    `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
  end

  def format_duration(seconds)
    if seconds < 60
      "#{seconds.round(1)}s"
    else
      minutes = (seconds / 60).floor
      remaining_seconds = (seconds % 60).round(1)
      "#{minutes}m #{remaining_seconds}s"
    end
  end

  def build_path(points)
    Tracks::BuildPath.new(points).call
  end

  def calculate_average_speed(distance_in_meters, duration_seconds)
    return 0.0 if duration_seconds <= 0 || distance_in_meters <= 0
    speed_mps = distance_in_meters.to_f / duration_seconds
    (speed_mps * 3.6).round(2)
  end

  def calculate_elevation_stats(points)
    altitudes = points.map(&:altitude).compact
    return { gain: 0, loss: 0, max: 0, min: 0 } if altitudes.empty?

    elevation_gain = 0
    elevation_loss = 0
    previous_altitude = altitudes.first

    altitudes[1..].each do |altitude|
      diff = altitude - previous_altitude
      if diff > 0
        elevation_gain += diff
      else
        elevation_loss += diff.abs
      end
      previous_altitude = altitude
    end

    { gain: elevation_gain.round, loss: elevation_loss.round, max: altitudes.max, min: altitudes.min }
  end
end

# Simple query monitor for this benchmark
class QueryMonitor
  attr_reader :query_count, :total_time_ms

  def initialize
    @query_count = 0
    @total_time_ms = 0
  end

  def start
    @subscription = ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      next if event.payload[:name]&.include?('SCHEMA')
      
      @query_count += 1
      @total_time_ms += event.duration
    end
  end

  def stop
    ActiveSupport::Notifications.unsubscribe(@subscription) if @subscription
  end
end

# Command line interface
if __FILE__ == $0
  if ARGV.length < 3
    puts "Usage: rails runner #{__FILE__} USER_ID START_DATE END_DATE"
    puts ""
    puts "Example:"
    puts "  rails runner #{__FILE__} 1 2024-01-01 2024-01-31"
    exit 1
  end

  user_id = ARGV[0].to_i
  start_date = ARGV[1]
  end_date = ARGV[2]

  benchmark = TracksOptimizationBenchmark.new(user_id, start_date, end_date)
  results = benchmark.run_all_benchmarks

  puts "\n🎉 Benchmark completed! Check results above."
end