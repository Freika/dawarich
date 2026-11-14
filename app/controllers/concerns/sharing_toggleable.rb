# frozen_string_literal: true

# Turns public sharing of a stat or digest on or off and answers the settings form.
module SharingToggleable
  private

  def toggle_sharing(record, i18n_scope, &)
    sharing_url, message = apply_sharing_toggle(record, i18n_scope, &)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace('sharing-link-display', partial: 'shared/sharing_link',
                                                       locals: { sharing_url: sharing_url }),
          stream_flash(:success, I18n.t("#{i18n_scope}.auto_saved"))
        ]
      end
      format.json { render json: { success: true, sharing_url: sharing_url, message: message } }
    end
  rescue StandardError
    render_sharing_failure(I18n.t("#{i18n_scope}.failed_to_update_sharing_settings"))
  end

  def apply_sharing_toggle(record, i18n_scope)
    if params[:enabled] == '1'
      record.enable_sharing!(expiration: params[:expiration] || '24h')
      [yield(record.sharing_uuid), I18n.t("#{i18n_scope}.sharing_enabled")]
    else
      record.disable_sharing!
      ['', I18n.t("#{i18n_scope}.sharing_disabled")]
    end
  end

  def render_sharing_failure(message)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: stream_flash(:error, message) }
      format.json { render json: { success: false, message: message }, status: :unprocessable_content }
    end
  end
end
