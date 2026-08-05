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
    message = I18n.t('services.families.create_location_request.an_error_occurred')
    Result.new(success?: false,
               payload: { message: message }, status: :internal_server_error)
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
      I18n.t('services.families.create_location_request.view_request'),
      Rails.application.routes.url_helpers.family_location_request_path(request),
      class: 'link link-primary'
    )

    I18n.with_locale(target_user.locale) do
      Notification.create!(
        user: target_user,
        kind: :info,
        title: I18n.t('services.families.create_location_request.location_request'),
        content: I18n.t('services.families.create_location_request.safe_email_is_requesting_your_location_link',
                        email: safe_email, link: link)
      )
    end
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to create notification for location request: #{e.message}")
  end

  def enqueue_email(request)
    FamilyMailer.location_request(request).deliver_later
  end

  def not_in_same_family_error
    message = I18n.t('services.families.create_location_request.users_must_be_in_the_same_family')
    Result.new(success?: false,
               payload: { message: message }, status: :forbidden)
  end

  def already_sharing_error
    message = I18n.t('services.families.create_location_request.target_user_is_already_sharing_their_location')
    Result.new(success?: false, payload: { message: message },
               status: :unprocessable_content)
  end

  def cooldown_error
    message = I18n.t(
      'services.families.create_location_request.request_cooldown_active_please_wait_before_requesting_again'
    )
    Result.new(success?: false, payload: { message: message },
               status: :too_many_requests)
  end
end
