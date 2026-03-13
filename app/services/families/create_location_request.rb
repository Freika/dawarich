# frozen_string_literal: true

class Families::CreateLocationRequest
  Result = Struct.new(:success?, :payload, :status, keyword_init: true)

  COOLDOWN_PERIOD = 1.hour

  def initialize(requester:, target_user:)
    @requester = requester
    @target_user = target_user
  end

  def call
    return not_in_same_family_error unless in_same_family?
    return already_sharing_error if target_user.family_sharing_enabled?
    return cooldown_error if cooldown_active?

    request = create_request!
    create_notification!(request)
    enqueue_email(request)

    Result.new(success?: true, payload: { request: request }, status: :created)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, payload: { message: e.message }, status: :unprocessable_content)
  rescue StandardError => e
    ExceptionReporter.call(e, "Error in Families::CreateLocationRequest: #{e.message}")
    Result.new(success?: false, payload: { message: 'An error occurred' }, status: :internal_server_error)
  end

  private

  attr_reader :requester, :target_user

  def in_same_family?
    requester.in_family? && target_user.in_family? && requester.family == target_user.family
  end

  def cooldown_active?
    Family::LocationRequest
      .where(requester: requester, target_user: target_user)
      .pending
      .where('created_at > ?', COOLDOWN_PERIOD.ago)
      .exists?
  end

  def create_request!
    Family::LocationRequest.create!(
      requester: requester,
      target_user: target_user,
      family: requester.family
    )
  end

  def create_notification!(request)
    safe_email = ERB::Util.html_escape(requester.email)
    link = ActionController::Base.helpers.link_to(
      'View Request',
      Rails.application.routes.url_helpers.family_location_request_path(request)
    )

    Notification.create!(
      user: target_user,
      kind: :info,
      title: 'Location Request',
      content: "#{safe_email} is requesting your location. #{link}"
    )
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to create notification for location request: #{e.message}")
  end

  def enqueue_email(request)
    FamilyMailer.location_request(request).deliver_later
  end

  def not_in_same_family_error
    Result.new(success?: false, payload: { message: 'Users must be in the same family' }, status: :forbidden)
  end

  def already_sharing_error
    Result.new(success?: false, payload: { message: 'Target user is already sharing their location' },
               status: :unprocessable_content)
  end

  def cooldown_error
    Result.new(success?: false, payload: { message: 'Request cooldown active. Please wait before requesting again.' },
               status: :too_many_requests)
  end
end
