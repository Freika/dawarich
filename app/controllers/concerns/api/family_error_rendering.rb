# frozen_string_literal: true

# Family API refusals share one shape, `{ error: <code>, message: <English> }`,
# so the apps can map the code to their own strings. Codes not listed here are
# business-rule refusals and answer 422.
module Api::FamilyErrorRendering
  extend ActiveSupport::Concern

  FAMILY_ERROR_STATUSES = {
    owner_required: :forbidden,
    email_mismatch: :forbidden,
    feature_disabled: :forbidden,
    family_plan_required: :forbidden,
    invitation_not_found: :not_found,
    member_not_found: :not_found,
    not_in_family: :not_found,
    rate_limited: :too_many_requests
  }.freeze

  FAMILY_ERROR_MESSAGES = {
    owner_required: 'Only the family owner can do this.',
    family_has_members: 'Remove all members before deleting the family.',
    invitation_not_found: 'Invitation not found.',
    invitation_invalid: 'This invitation is no longer valid or has expired.',
    member_not_found: 'Member not found.',
    rate_limited: 'Too many invitations, try again later.',
    unexpected_error: 'Something went wrong, please try again.'
  }.freeze

  private

  def ensure_user_in_family!
    return if current_api_user&.in_family?

    render_family_error(:not_in_family, I18n.t('controllers.api.v1.families.locations.user_is_not_part_of_a_family'))
  end

  def render_family_error(code, message = nil, status = nil)
    code = code.to_sym
    message = message.presence || FAMILY_ERROR_MESSAGES.fetch(code, FAMILY_ERROR_MESSAGES[:unexpected_error])
    render json: { error: code.to_s, message: message },
           status: status || FAMILY_ERROR_STATUSES.fetch(code, :unprocessable_content)
  end

  # Validation refusals keep their text in `errors`, not in `error_message`.
  def render_family_service_error(service)
    message = service.error_message.presence
    message ||= service.errors.first&.message if service.respond_to?(:errors)
    render_family_error(service.error_code || :unexpected_error, message)
  end
end
