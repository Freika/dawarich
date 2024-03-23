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
    imports = []
    success = true

    files.each do |file|
      json = JSON.parse(file.read)
      import = current_user.imports.create(name: file.original_filename, source: params[:import][:source])
      parser.new(file.path, import.id).call

      imports << import
    end

    redirect_to imports_url, notice: "#{imports.count} imports was successfully created.", status: :see_other

  rescue StandardError => e
    imports.each { |import| import&.destroy! }

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

  def parser
    case params[:import][:source]
    when 'google' then GoogleMaps::TimelineParser
    when 'owntracks' then OwnTracks::ExportParser
    end
  end
end
