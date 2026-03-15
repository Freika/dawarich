# frozen_string_literal: true

class FamilyMailer < ApplicationMailer
  def invitation(invitation)
    @invitation = invitation
    @family = invitation.family
    @invited_by = invitation.invited_by
    @accept_url = family_invitation_url(@invitation.token)

    mail(
      to: @invitation.email,
      subject: "🎉 You've been invited to join #{@family.name} on Dawarich!"
    )
  end

  def location_request(request)
    @request = request
    @requester = request.requester
    @target_user = request.target_user
    @request_url = family_location_request_url(request)

    mail(
      to: @target_user.email,
      subject: "📍 #{@requester.email} is requesting your location on Dawarich"
    )
  end

  def member_joined(family, user)
    @family = family
    @user = user

    mail(
      to: @family.owner.email,
      subject: "👪 #{@user.name} has joined your family #{@family.name} on Dawarich!"
    )
  end
end
