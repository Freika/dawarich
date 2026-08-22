# frozen_string_literal: true

class Families::RespondToLocationRequest
  Result = Struct.new(:success?, :payload, :status, keyword_init: true)

  def initialize(request:, responder:, decision:, duration: nil)
    @request = request
    @responder = responder
    @decision = decision
    @duration = duration
  end

  def call
    return not_authorized_error unless request.target_user == responder
    return not_actionable_error unless actionable?

    decision == :accept ? accept! : decline!
    Result.new(success?: true, payload: { success: true, status: request.status }, status: :ok)
  rescue StandardError => e
    ExceptionReporter.call(e, "Error in Families::RespondToLocationRequest: #{e.message}")
    Result.new(success?: false,
               payload: { message: I18n.t('services.families.respond_to_location_request.an_error_occurred') },
               status: :internal_server_error)
  end

  private

  attr_reader :request, :responder, :decision, :duration

  def actionable?
    request.pending? && request.expires_at > Time.current
  end

  def accept!
    ActiveRecord::Base.transaction do
      responder.update_family_location_sharing!(true, duration: duration.presence || request.suggested_duration)
      request.update!(status: :accepted, responded_at: Time.current)
    end
  end

  def decline!
    request.update!(status: :declined, responded_at: Time.current)
  end

  def not_authorized_error
    Result.new(success?: false,
               payload: { message: I18n.t('services.families.respond_to_location_request.not_authorized') },
               status: :forbidden)
  end

  def not_actionable_error
    Result.new(success?: false,
               payload: { message: I18n.t('services.families.respond_to_location_request.no_longer_actionable') },
               status: :unprocessable_content)
  end
end
