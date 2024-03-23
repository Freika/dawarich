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
    report = ''

    files.each do |file|
      json = JSON.parse(file.read)
      import = current_user.imports.create(name: file.original_filename, source: params[:import][:source])
      result = parser.new(file.path, import.id).call

      if result[:points].zero?
        import.destroy!
      else
        import.update(raw_points: result[:raw_points], doubles: result[:doubles])

        imports << import
      end
    end

    StatCreatingJob.perform_later(current_user.id)

    redirect_to imports_url, notice: "#{imports.size} import files were imported successfully", status: :see_other
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
