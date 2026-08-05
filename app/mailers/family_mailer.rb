# frozen_string_literal: true

class FamilyMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @family = invitation.family
    @invited_by = invitation.invited_by
    @accept_url = family_invitation_url(@invitation.token)

    with_user_locale(@invited_by) do
      mail(
        to: @invitation.email,
        subject: I18n.t('mailers.family.invitation.subject', family: @family.name)
      )
    end
  end

  def location_request(request)
    @request = request
    @requester = request.requester
    @target_user = request.target_user
    @request_url = family_location_request_url(request)

    with_user_locale(@target_user) do
      mail(
        to: @target_user.email,
        subject: I18n.t('mailers.family.location_request.subject', requester: @requester.email)
      )
    end
  end

  def member_joined(family, user)
    @family = family
    @user = user

    with_user_locale(@family.owner) do
      mail(
        to: @family.owner.email,
        subject: I18n.t('mailers.family.member_joined.subject', user: @user.email, family: @family.name)
      )
    end
  end
end
