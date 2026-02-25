# frozen_string_literal: true

class ExportsController < ApplicationController
  include ActiveStorage::SetCurrent

  before_action :authenticate_user!
  before_action :set_export, only: %i[destroy]

  def index
    scope = current_user.exports.with_attached_file
    @exports = sorted(scope).page(params[:page])
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

  def sorted(scope)
    if sort_column == 'byte_size'
      scope.joins(file_attachment: :blob).order("active_storage_blobs.byte_size #{sort_direction}")
    else
      scope.order(sort_column => sort_direction)
    end
  end

  def sort_column
    %w[name status created_at byte_size].include?(params[:sort_by]) ? params[:sort_by] : 'created_at'
  end

  def sort_direction
    %w[asc desc].include?(params[:order_by]) ? params[:order_by] : 'desc'
  end
end
