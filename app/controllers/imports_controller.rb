# frozen_string_literal: true

class ImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[new create]
  before_action :set_import, only: %i[show destroy]

  def index
    @imports =
      current_user
      .imports
      .select(:id, :name, :source, :created_at, :points_count)
      .order(created_at: :desc)
      .page(params[:page])
  end

  def show; end

  def new
    @import = Import.new
  end

  def create
    files = import_params[:files].reject(&:blank?)

    files.each do |file|
      import = current_user.imports.build(
        name: file.original_filename,
        source: params[:import][:source]
      )

      import.file.attach(io: file, filename: file.original_filename, content_type: file.content_type)

      import.save!
    end

    redirect_to imports_url, notice: "#{files.size} files are queued to be imported in background", status: :see_other
  rescue StandardError => e
    Import.where(user: current_user, name: files.map(&:original_filename)).destroy_all

    flash.now[:error] = e.message

    redirect_to new_import_path, notice: e.message, status: :unprocessable_entity
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
end
