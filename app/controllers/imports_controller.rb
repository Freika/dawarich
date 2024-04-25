class ImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_import, only: %i[ show destroy ]

  def index
    @imports = current_user.imports
  end

  def show
  end

  def new
    @import = Import.new
  end

  def create
    files = import_params[:files].reject(&:blank?)

    import_ids = files.map do |file|
      import = current_user.imports.create(
        name: file.original_filename,
        source: params[:import][:source]
      )

      import.update(raw_data: JSON.parse(File.read(file)))
      import.id
    end

    import_ids.each do |import_id|
      ImportJob.set(wait: 5.seconds).perform_later(current_user.id, import_id)
    end

    redirect_to imports_url, notice: "#{files.size} files are queued to be imported in background", status: :see_other
  rescue StandardError => e
    Import.where(user: current_user, name: files.map(&:original_filename)).destroy_all

    flash.now[:error] = e.message

    redirect_to new_import_path, notice: e.message, status: :unprocessable_entity
  end

  def destroy
    @import.destroy!
    redirect_to imports_url, notice: "Import was successfully destroyed.", status: :see_other
  end

  private

  def set_import
    @import = Import.find(params[:id])
  end

  def import_params
    params.require(:import).permit(:source, files: [])
  end
end
