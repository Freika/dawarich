# frozen_string_literal: true

class FamilyMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @family = invitation.family
    @invited_by = invitation.invited_by
    @accept_url = family_invitation_url(@invitation.token)

    mail(
      to: @invitation.email,
      subject: I18n.t('mailers.family.invitation.subject', family: @family.name)
    )
  end

  def location_request(request)
    @request = request
    @requester = request.requester
    @target_user = request.target_user
    @request_url = family_location_request_url(request)

    mail(
      to: @target_user.email,
      subject: I18n.t('mailers.family.location_request.subject', requester: @requester.email)
    )
  end

  def member_joined(family, user)
    @family = family
    @user = user

    mail(
      to: @family.owner.email,
      subject: I18n.t('mailers.family.member_joined.subject', user: @user.name, family: @family.name)
    )
  end
end
