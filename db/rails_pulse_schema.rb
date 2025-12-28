# Rails Pulse Database Schema
# This file contains the complete schema for Rails Pulse tables
# Load with: rails db:schema:load:rails_pulse or db:prepare

RailsPulse::Schema = lambda do |connection|
  # Skip if all tables already exist to prevent conflicts
  required_tables = [ :rails_pulse_routes, :rails_pulse_queries, :rails_pulse_requests, :rails_pulse_operations, :rails_pulse_summaries ]

  if ENV["CI"] == "true"
    existing_tables = required_tables.select { |table| connection.table_exists?(table) }
    missing_tables = required_tables - existing_tables
    puts "[RailsPulse::Schema] Existing tables: #{existing_tables.join(', ')}" if existing_tables.any?
    puts "[RailsPulse::Schema] Missing tables: #{missing_tables.join(', ')}" if missing_tables.any?
  end

  return if required_tables.all? { |table| connection.table_exists?(table) }

  connection.create_table :rails_pulse_routes do |t|
    t.string :method, null: false, comment: "HTTP method (e.g., GET, POST)"
    t.string :path, null: false, comment: "Request path (e.g., /posts/index)"
    t.text :tags, comment: "JSON array of tags for filtering and categorization"
    t.timestamps
  end

  connection.add_index :rails_pulse_routes, [ :method, :path ], unique: true, name: "index_rails_pulse_routes_on_method_and_path"

  connection.create_table :rails_pulse_queries do |t|
    t.string :normalized_sql, limit: 1000, null: false, comment: "Normalized SQL query string (e.g., SELECT * FROM users WHERE id = ?)"
    t.datetime :analyzed_at, comment: "When query analysis was last performed"
    t.text :explain_plan, comment: "EXPLAIN output from actual SQL execution"
    t.text :issues, comment: "JSON array of detected performance issues"
    t.text :metadata, comment: "JSON object containing query complexity metrics"
    t.text :query_stats, comment: "JSON object with query characteristics analysis"
    t.text :backtrace_analysis, comment: "JSON object with call chain and N+1 detection"
    t.text :index_recommendations, comment: "JSON array of database index recommendations"
    t.text :n_plus_one_analysis, comment: "JSON object with enhanced N+1 query detection results"
    t.text :suggestions, comment: "JSON array of optimization recommendations"
    t.text :tags, comment: "JSON array of tags for filtering and categorization"
    t.timestamps
  end

  connection.add_index :rails_pulse_queries, :normalized_sql, unique: true, name: "index_rails_pulse_queries_on_normalized_sql", length: 191

  connection.create_table :rails_pulse_requests do |t|
    t.references :route, null: false, foreign_key: { to_table: :rails_pulse_routes }, comment: "Link to the route"
    t.decimal :duration, precision: 15, scale: 6, null: false, comment: "Total request duration in milliseconds"
    t.integer :status, null: false, comment: "HTTP status code (e.g., 200, 500)"
    t.boolean :is_error, null: false, default: false, comment: "True if status >= 500"
    t.string :request_uuid, null: false, comment: "Unique identifier for the request (e.g., UUID)"
    t.string :controller_action, comment: "Controller and action handling the request (e.g., PostsController#show)"
    t.timestamp :occurred_at, null: false, comment: "When the request started"
    t.text :tags, comment: "JSON array of tags for filtering and categorization"
    t.timestamps
  end

  connection.add_index :rails_pulse_requests, :occurred_at, name: "index_rails_pulse_requests_on_occurred_at"
  connection.add_index :rails_pulse_requests, :request_uuid, unique: true, name: "index_rails_pulse_requests_on_request_uuid"
  connection.add_index :rails_pulse_requests, [ :route_id, :occurred_at ], name: "index_rails_pulse_requests_on_route_id_and_occurred_at"

  connection.create_table :rails_pulse_operations do |t|
    t.references :request, null: false, foreign_key: { to_table: :rails_pulse_requests }, comment: "Link to the request"
    t.references :query, foreign_key: { to_table: :rails_pulse_queries }, index: true, comment: "Link to the normalized SQL query"
    t.string :operation_type, null: false, comment: "Type of operation (e.g., database, view, gem_call)"
    t.string :label, null: false, comment: "Descriptive name (e.g., SELECT FROM users WHERE id = 1, render layout)"
    t.decimal :duration, precision: 15, scale: 6, null: false, comment: "Operation duration in milliseconds"
    t.string :codebase_location, comment: "File and line number (e.g., app/models/user.rb:25)"
    t.float :start_time, null: false, default: 0.0, comment: "Operation start time in milliseconds"
    t.timestamp :occurred_at, null: false, comment: "When the request started"
    t.timestamps
  end

  connection.add_index :rails_pulse_operations, :operation_type, name: "index_rails_pulse_operations_on_operation_type"
  connection.add_index :rails_pulse_operations, :occurred_at, name: "index_rails_pulse_operations_on_occurred_at"
  connection.add_index :rails_pulse_operations, [ :query_id, :occurred_at ], name: "index_rails_pulse_operations_on_query_and_time"
  connection.add_index :rails_pulse_operations, [ :query_id, :duration, :occurred_at ], name: "index_rails_pulse_operations_query_performance"
  connection.add_index :rails_pulse_operations, [ :occurred_at, :duration, :operation_type ], name: "index_rails_pulse_operations_on_time_duration_type"

  connection.create_table :rails_pulse_summaries do |t|
    # Time fields
    t.datetime :period_start, null: false, comment: "Start of the aggregation period"
    t.datetime :period_end, null: false, comment: "End of the aggregation period"
    t.string :period_type, null: false, comment: "Aggregation period type: hour, day, week, month"

    # Polymorphic association to handle both routes and queries
    t.references :summarizable, polymorphic: true, null: false, index: true, comment: "Link to Route or Query"
    # This creates summarizable_type (e.g., 'RailsPulse::Route', 'RailsPulse::Query')
    # and summarizable_id (route_id or query_id)

    # Universal metrics
    t.integer :count, default: 0, null: false, comment: "Total number of requests/operations"
    t.float :avg_duration, comment: "Average duration in milliseconds"
    t.float :min_duration, comment: "Minimum duration in milliseconds"
    t.float :max_duration, comment: "Maximum duration in milliseconds"
    t.float :p50_duration, comment: "50th percentile duration"
    t.float :p95_duration, comment: "95th percentile duration"
    t.float :p99_duration, comment: "99th percentile duration"
    t.float :total_duration, comment: "Total duration in milliseconds"
    t.float :stddev_duration, comment: "Standard deviation of duration"

    # Request/Route specific metrics
    t.integer :error_count, default: 0, comment: "Number of error responses (5xx)"
    t.integer :success_count, default: 0, comment: "Number of successful responses"
    t.integer :status_2xx, default: 0, comment: "Number of 2xx responses"
    t.integer :status_3xx, default: 0, comment: "Number of 3xx responses"
    t.integer :status_4xx, default: 0, comment: "Number of 4xx responses"
    t.integer :status_5xx, default: 0, comment: "Number of 5xx responses"

    t.timestamps
  end

  # Unique constraint and indexes for summaries
  connection.add_index :rails_pulse_summaries, [ :summarizable_type, :summarizable_id, :period_type, :period_start ],
          unique: true,
          name: "idx_pulse_summaries_unique"
  connection.add_index :rails_pulse_summaries, [ :period_type, :period_start ], name: "index_rails_pulse_summaries_on_period"
  connection.add_index :rails_pulse_summaries, :created_at, name: "index_rails_pulse_summaries_on_created_at"

  # Add indexes to existing tables for efficient aggregation
  connection.add_index :rails_pulse_requests, [ :created_at, :route_id ], name: "idx_requests_for_aggregation"
  connection.add_index :rails_pulse_requests, :created_at, name: "idx_requests_created_at"

  connection.add_index :rails_pulse_operations, [ :created_at, :query_id ], name: "idx_operations_for_aggregation"
  connection.add_index :rails_pulse_operations, :created_at, name: "idx_operations_created_at"

  if ENV["CI"] == "true"
    created_tables = required_tables.select { |table| connection.table_exists?(table) }
    puts "[RailsPulse::Schema] Successfully created tables: #{created_tables.join(', ')}"
  end
end

if defined?(RailsPulse::ApplicationRecord)
  RailsPulse::Schema.call(RailsPulse::ApplicationRecord.connection)
end
