# frozen_string_literal: true

class ImportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create]
  before_action :set_import, only: %i[show edit update destroy]
  before_action :validate_points_limit, only: %i[new create]
  def index
    @imports =
      current_user
      .imports
      .select(:id, :name, :source, :created_at, :processed)
      .order(created_at: :desc)
      .page(params[:page])
  end

  def show; end

  def edit; end

  def new
    @import = Import.new
  end

  def update
    @import.update(import_params)

    redirect_to imports_url, notice: 'Import was successfully updated.', status: :see_other
  end

  def create
    files_params = params.dig(:import, :files)
    raw_files = Array(files_params).reject(&:blank?)

    if raw_files.empty?
      redirect_to new_import_path, alert: 'No files were selected for upload', status: :unprocessable_entity
      return
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
                  status: :see_other
    else
      redirect_to new_import_path,
                  alert: 'No valid file references were found. Please upload files using the file selector.',
                  status: :unprocessable_entity
    end
  rescue StandardError => e
    if created_imports.present?
      import_ids = created_imports.map(&:id).compact
      Import.where(id: import_ids).destroy_all if import_ids.any?
    end

    Rails.logger.error "Import error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    ExceptionReporter.call(e)

    redirect_to new_import_path, alert: e.message, status: :unprocessable_entity
  end

  def destroy
    Imports::Destroy.new(current_user, @import).call

    redirect_to imports_url, notice: 'Import was successfully destroyed.', status: :see_other
  end

  private

  def set_import
    @import = Import.find(params[:id])
  end

  def import_params
    params.require(:import).permit(:source, files: [])
  end

  def create_import_from_signed_id(signed_id)
    Rails.logger.debug "Creating import from signed ID: #{signed_id[0..20]}..."

    blob = ActiveStorage::Blob.find_signed(signed_id)

    import = current_user.imports.build(
      name: blob.filename.to_s,
      source: params[:import][:source]
    )

    import.file.attach(blob)

    import.save!

    import
  end

  def validate_points_limit
    limit_exceeded = PointsLimitExceeded.new(current_user).call

    redirect_to new_import_path, alert: 'Points limit exceeded', status: :unprocessable_entity if limit_exceeded
  end
end
