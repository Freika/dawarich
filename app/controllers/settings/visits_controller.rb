# frozen_string_literal: true

# Visit detection moved into Settings → Data processing. The old page and the
# links in earlier notifications land on its section there.
class Settings::VisitsController < ApplicationController
  before_action :authenticate_user!

  def show
    redirect_to settings_data_processing_path(anchor: 'visits')
  end
end
