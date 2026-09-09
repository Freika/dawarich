# frozen_string_literal: true

class Api::V1::Imports::PendingController < ApiController
  skip_before_action :authenticate_api_key, raise: false
  skip_before_action :reject_pending_payment!, raise: false
  skip_before_action :authenticate_active_api_user!, raise: false

  include OriginAllowlistable
  before_action :ensure_cloud!
  before_action :enforce_origin_allowlist!

  ALLOWED_EXTENSIONS = %w[.gpx .geojson .json .kml .kmz .rec .csv .tcx .fit .zip].freeze
  MAX_BYTE_SIZE = 100.megabytes
  STORAGE_QUOTA_BYTES = 10.gigabytes

  def create
    unless file_param.is_a?(ActionDispatch::Http::UploadedFile)
      return render_error(:bad_request,
                          I18n.t('controllers.api.v1.imports.pending.missing_file'))
    end
    if params[:original_filename].blank?
      return render_error(:bad_request,
                          I18n.t('controllers.api.v1.imports.pending.missing_filename'))
    end
    unless file_param.size.positive?
      return render_error(:unprocessable_entity,
                          I18n.t('controllers.api.v1.imports.pending.empty_file'))
    end
    if file_param.size > MAX_BYTE_SIZE
      return render_error(:payload_too_large,
                          I18n.t('controllers.api.v1.imports.pending.file_too_large'))
    end
    unless allowed_extension?
      return render_error(
        :unprocessable_entity,
        I18n.t('controllers.api.v1.imports.pending.unsupported_file_type', extension: file_extension)
      )
    end

    quota_key = storage_quota_key
    unless reserve_storage(file_param.size, quota_key)
      return render_error(:too_many_requests, I18n.t('controllers.api.v1.imports.pending.storage_capacity_exceeded'))
    end

    storage_reservation = [file_param.size, quota_key]

    pending = PendingImport.new(
      original_filename: params[:original_filename],
      source_hint: params[:source_hint],
      origin: request.origin,
      expires_at: 24.hours.from_now
    )
    pending.file.attach(
      io: file_param.tempfile,
      filename: params[:original_filename],
      content_type: file_param.content_type || 'application/zip'
    )
    pending.save!

    render json: {
      claim_ticket: pending.claim_ticket,
      expires_at: pending.expires_at.iso8601,
      claim_url: build_claim_url(pending.claim_ticket)
    }, status: :created
  rescue StandardError => e
    release_storage(*storage_reservation) if storage_reservation
    Rails.logger.error("PendingImport create failed: #{e.message}")
    ExceptionReporter.call(e) if defined?(ExceptionReporter)
    render json: { error: I18n.t('controllers.api.v1.imports.pending.an_error_occurred') },
           status: :internal_server_error
  end

  private

  # The tools handoff is a Cloud acquisition funnel; self-hosted instances
  # have no dawarich.app tools pointing at them — don't expose the surface.
  def ensure_cloud!
    head :not_found if DawarichSettings.self_hosted?
  end

  def file_param
    params[:file]
  end

  def file_extension
    File.extname(params[:original_filename].to_s).downcase
  end

  def allowed_extension?
    ALLOWED_EXTENSIONS.include?(file_extension)
  end

  def reserve_storage(bytes, key)
    used = Rails.cache.increment(key, bytes, expires_in: 2.days)
    return true if used <= STORAGE_QUOTA_BYTES

    Rails.cache.decrement(key, bytes)
    false
  end

  def release_storage(bytes, key)
    Rails.cache.decrement(key, bytes)
  end

  def storage_quota_key
    "pending_imports/storage_bytes/#{Time.current.utc.to_date}"
  end

  def render_error(status, message)
    render json: { error: message }, status: status
  end

  # The signup that claims the ticket lives on the same host that served
  # this request — no configuration needed, works on any environment.
  def build_claim_url(ticket)
    "#{request.base_url}/users/sign_up?import_ticket=#{ticket}&utm_source=tool&utm_medium=save-to-account"
  end
end
