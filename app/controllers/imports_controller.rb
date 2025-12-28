# frozen_string_literal: true

class ImportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_import, only: %i[show edit update destroy]
  before_action :authorize_import, only: %i[show edit update destroy]
  before_action :validate_points_limit, only: %i[new create]

  after_action :verify_authorized, except: %i[index]
  after_action :verify_policy_scoped, only: %i[index]

  def index
    @imports = policy_scope(Import)
               .select(:id, :name, :source, :created_at, :processed, :status)
               .with_attached_file
               .order(created_at: :desc)
               .page(params[:page])
  end

  def show; end

  def edit; end

  def new
    @import = Import.new

    authorize @import
  end

  def update
    @import.update(import_params)

    redirect_to imports_url, notice: 'Import was successfully updated.', status: :see_other
  end

  def create
    @import = Import.new

    authorize @import

    files_params = params.dig(:import, :files)
    raw_files = Array(files_params).reject(&:blank?)

    if raw_files.empty?
      redirect_to new_import_path, alert: 'No files were selected for upload', status: :unprocessable_content and return
    end

    created_imports = []

    raw_files.each do |item|
      next if item.is_a?(ActionDispatch::Http::UploadedFile)

      import = create_import_from_signed_id(item)
      created_imports << import if import.present?
    end

    if created_imports.any?
      redirect_to imports_url,
                  notice: "#{created_imports.size} files are queued to be imported in background",
                  status: :see_other and return
    else
      redirect_to new_import_path,
                  alert: 'No valid file references were found. Please upload files using the file selector.',
                  status: :unprocessable_content and return
    end
  rescue StandardError => e
    if created_imports.present?
      import_ids = created_imports.map(&:id).compact
      Import.where(id: import_ids).destroy_all if import_ids.any?
    end

    Rails.logger.error "Import error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    ExceptionReporter.call(e)

    redirect_to new_import_path, alert: e.message, status: :unprocessable_content
  end

  def destroy
    @import.deleting!
    Imports::DestroyJob.perform_later(@import.id)

    respond_to do |format|
      format.html { redirect_to imports_url, notice: 'Import is being deleted.', status: :see_other }
      format.turbo_stream
    end
  end

  private

  def set_import
    @import = Import.find(params[:id])
  end

  def authorize_import
    authorize @import
  end

  def import_params
    params.require(:import).permit(:name, files: [])
  end

  def create_import_from_signed_id(signed_id)
    Rails.logger.debug "Creating import from signed ID: #{signed_id[0..20]}..."

    blob = ActiveStorage::Blob.find_signed(signed_id)

    import_name = generate_unique_import_name(blob.filename.to_s)
    import = current_user.imports.build(name: import_name)
    import.file.attach(blob)

    import.save!

    import
  end

  def generate_unique_import_name(original_name)
    return original_name unless current_user.imports.exists?(name: original_name)

    # Extract filename and extension
    basename = File.basename(original_name, File.extname(original_name))
    extension = File.extname(original_name)

    # Add current datetime
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    "#{basename}_#{timestamp}#{extension}"
  end

  def validate_points_limit
    limit_exceeded = PointsLimitExceeded.new(current_user).call

    redirect_to imports_path, alert: 'Points limit exceeded', status: :unprocessable_content if limit_exceeded
  end
end
