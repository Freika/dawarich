class ExportController < ApplicationController
  before_action :authenticate_user!

  def index
    @export = current_user.export_data
  end
end
