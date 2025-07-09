# frozen_string_literal: true

class Tracks::CreateFromPoints
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  attr_reader :user, :start_at, :end_at, :cleaning_strategy

  def initialize(user, start_at: nil, end_at: nil, cleaning_strategy: :replace)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @cleaning_strategy = cleaning_strategy
  end

  def call
    generator = Tracks::Generator.new(
      user,
      point_loader: point_loader,
      incomplete_segment_handler: incomplete_segment_handler,
      track_cleaner: track_cleaner
    )

    generator.call
  end

  # Expose threshold properties for tests
  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i || 500
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i || 60
  end

  private

  def point_loader
    @point_loader ||=
      Tracks::PointLoaders::BulkLoader.new(
        user, start_at: start_at, end_at: end_at
      )
  end

  def incomplete_segment_handler
    @incomplete_segment_handler ||=
      Tracks::IncompleteSegmentHandlers::IgnoreHandler.new(user)
  end

    def track_cleaner
    @track_cleaner ||=
      case cleaning_strategy
      when :daily
        Tracks::Cleaners::DailyCleaner.new(user, start_at: start_at, end_at: end_at)
      when :none
        Tracks::Cleaners::NoOpCleaner.new(user)
      else # :replace (default)
        Tracks::Cleaners::ReplaceCleaner.new(user, start_at: start_at, end_at: end_at)
      end
  end

  # Legacy method for backward compatibility with tests
  # Delegates to segmentation module logic
  def should_start_new_track?(current_point, previous_point)
    should_start_new_segment?(current_point, previous_point)
  end

  # Legacy method for backward compatibility with tests
  # Delegates to segmentation module logic
  def calculate_distance_kilometers(point1, point2)
    calculate_distance_kilometers_between_points(point1, point2)
  end
end
