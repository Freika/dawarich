# frozen_string_literal: true

class Api::V1::ImportsController < ApiController
  ALLOWED_EXTENSIONS = %w[.gpx .geojson .json .kml .kmz .rec .csv].freeze

  before_action :authenticate_active_api_user!, only: %i[create]
  before_action :require_write_api!, only: %i[create]
  before_action :validate_points_limit, only: %i[create]
  before_action :validate_file_type, only: %i[create]

  def index
    imports = current_api_user
              .imports
              .select(:id, :name, :source, :status, :created_at, :processed, :points_count, :error_message)
              .order(created_at: :desc)
              .page(params[:page])
              .per([params.fetch(:per_page, 25).to_i, 100].min)

    response.set_header('X-Current-Page', imports.current_page.to_s)
    response.set_header('X-Total-Pages', imports.total_pages.to_s)

    render json: imports.map { |i| serialize_import(i) }
  end

  def show
    import = current_api_user.imports.find(params[:id])

    render json: serialize_import(import)
  end

  def create
    unless params[:file].is_a?(ActionDispatch::Http::UploadedFile)
      render json: { error: 'Missing required parameter: file' }, status: :unprocessable_entity and return
    end

    uploaded_file = params[:file]
    import_name = generate_unique_import_name(uploaded_file.original_filename)

    import = current_api_user.imports.build(name: import_name)
    import.file.attach(
      io: uploaded_file.tempfile,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type || 'application/octet-stream'
    )

    if import.save
      render json: serialize_import(import), status: :created
    else
      render json: { error: import.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "API Import error: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    ExceptionReporter.call(e)
    render json: { error: 'An error occurred while processing the import' }, status: :internal_server_error
  end

  private

  def generate_unique_import_name(original_name)
    return original_name unless current_api_user.imports.exists?(name: original_name)

    basename = File.basename(original_name, File.extname(original_name))
    extension = File.extname(original_name)
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    "#{basename}_#{timestamp}#{extension}"
  end

  def validate_file_type
    return unless params[:file].is_a?(ActionDispatch::Http::UploadedFile)

    ext = File.extname(params[:file].original_filename).downcase
    return if ALLOWED_EXTENSIONS.include?(ext)

    render json: {
      error: "Unsupported file type '#{ext}'. Allowed: #{ALLOWED_EXTENSIONS.join(', ')}"
    }, status: :unprocessable_entity
  end

  def serialize_import(import)
    {
      id: import.id,
      name: import.name,
      source: import.source,
      status: import.status,
      created_at: import.created_at,
      points_count: import.points_count,
      processed: import.processed,
      error_message: import.error_message
    }
  end
end
