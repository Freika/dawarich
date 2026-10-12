# frozen_string_literal: true

module Imports
  class ExtractionsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_import

    def create
      authorize @import, policy_class: Imports::ExtractionPolicy

      trust_source = ActiveModel::Type::Boolean.new.cast(params.fetch(:trust_source, true))
      payload = @import.additional_data_extraction.merge(
        'options' => { 'trust_source' => trust_source },
        'started_at' => Time.current.iso8601
      )

      EnhancedImport::ExtractJob.perform_later(@import.id) if @import.claim_additional_data_extraction!(payload)
      @import.reload

      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_to import_path(@import), notice: I18n.t('controllers.imports.extractions.extraction_queued')
        end
      end
    end

    def destroy
      authorize @import, policy_class: Imports::ExtractionPolicy

      @import.update_columns(
        additional_data_extraction_status: Import.additional_data_extraction_statuses[:running],
        additional_data_extraction: @import.additional_data_extraction.merge('started_at' => Time.current.iso8601)
      )

      EnhancedImport::DestroyJob.perform_later(@import.id)

      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_to import_path(@import), notice: I18n.t('controllers.imports.extractions.removing_extracted_data')
        end
      end
    end

    private

    def set_import
      @import = Import.find(params[:import_id])
    end
  end
end
