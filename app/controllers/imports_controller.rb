# frozen_string_literal: true

class ImportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create]
  before_action :set_import, only: %i[show edit update destroy]

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
    raw_files = params.dig(:import, :files).reject(&:blank?)

    if raw_files.empty?
      redirect_to new_import_path, alert: 'No files were selected for upload', status: :unprocessable_entity
      return
    end

    imports = raw_files.map do |item|
      next if item.is_a?(ActionDispatch::Http::UploadedFile)

      Rails.logger.debug "Processing signed ID: #{item[0..20]}..."

      create_import_from_signed_id(item)
    end

    if imports.any?
      redirect_to imports_url,
                  notice: "#{imports.size} files are queued to be imported in background",
                  status: :see_other
    else
      redirect_to new_import_path,
                  alert: 'No valid file references were found. Please upload files using the file selector.',
                  status: :unprocessable_entity
    end
  rescue StandardError => e
    # Clean up recent imports if there was an error
    Import.where(user: current_user).where('created_at > ?', 5.minutes.ago).destroy_all

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

    # Find the blob using the signed ID
    blob = ActiveStorage::Blob.find_signed(signed_id)

    # Create the import
    import = current_user.imports.build(
      name: blob.filename.to_s,
      source: params[:import][:source]
    )

    # Attach the blob to the import
    import.file.attach(blob)

    import.save!

    import
  end
end
