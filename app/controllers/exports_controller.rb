# frozen_string_literal: true

class ExportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_export, only: %i[destroy]

  def index
    @exports = current_user.exports.order(created_at: :desc).page(params[:page])
  end

  def create
    export_name =
      "export_from_#{params[:start_at].to_date}_to_#{params[:end_at].to_date}.#{params[:file_format]}"
    export = current_user.exports.create(
      name: export_name,
      status: :created,
      file_format: params[:file_format],
      start_at: params[:start_at],
      end_at: params[:end_at]
    )

    redirect_to exports_url, notice: 'Export was successfully initiated. Please wait until it\'s finished.'
  rescue StandardError => e
    export&.destroy

    ExceptionReporter.call(e)

    redirect_to exports_url, alert: "Export failed to initiate: #{e.message}", status: :unprocessable_content
  end

  def destroy
    @export.destroy

    redirect_to exports_url, notice: 'Export was successfully destroyed.', status: :see_other
  end

  private

  def set_export
    @export = current_user.exports.find(params[:id])
  end
end
