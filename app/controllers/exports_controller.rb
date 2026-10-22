# frozen_string_literal: true

class ExportsController < ApplicationController
  include ActiveStorage::SetCurrent
  include Sortable

  SORTABLE_COLUMNS = %w[name status created_at byte_size].freeze

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

    redirect_to exports_url,
                notice: I18n.t('controllers.exports.export_was_successfully_initiated_please_wait_until_it_s_finished')
  rescue StandardError => e
    export&.destroy

    ExceptionReporter.call(e)

    redirect_to exports_url, alert: I18n.t('controllers.exports.export_failed_to_initiate_please_try_again'),
status: :unprocessable_content
  end

  def destroy
    @export.destroy

    redirect_to exports_url, notice: I18n.t('controllers.exports.export_was_successfully_destroyed'), status: :see_other
  end

  private

  def set_export
    @export = current_user.exports.find(params[:id])
  end
end
