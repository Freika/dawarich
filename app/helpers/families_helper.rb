# frozen_string_literal: true

module FamiliesHelper
  def family_member_role_badge(membership)
    case membership.role
    when 'owner'
      content_tag :span, 'Owner', class: 'badge badge-primary badge-sm'
    when 'member'
      content_tag :span, 'Member', class: 'badge badge-secondary badge-sm'
    else
      content_tag :span, membership.role.humanize, class: 'badge badge-ghost badge-sm'
    end
  end

  def family_invitation_status_badge(invitation)
    case invitation.status
    when 'pending'
      content_tag :span, 'Pending', class: 'badge badge-warning badge-sm'
    when 'accepted'
      content_tag :span, 'Accepted', class: 'badge badge-success badge-sm'
    when 'expired'
      content_tag :span, 'Expired', class: 'badge badge-error badge-sm'
    when 'cancelled'
      content_tag :span, 'Cancelled', class: 'badge badge-ghost badge-sm'
    else
      content_tag :span, invitation.status.humanize, class: 'badge badge-ghost badge-sm'
    end
  end

  def family_capacity_warning(family)
    return unless family.members.count >= Family::MAX_MEMBERS - 1

    content_tag :div, class: 'alert alert-warning mt-2' do
      content_tag :div do
        if family.members.count >= Family::MAX_MEMBERS
          'This family has reached the maximum number of members.'
        else
          "This family is almost full (#{family.members.count}/#{Family::MAX_MEMBERS} members)."
        end
      end
    end
  end

  def invitation_expiry_warning(invitation)
    return unless invitation.pending?

    time_left = invitation.expires_at - Time.current
    return unless time_left < 24.hours

    warning_class = time_left < 1.hour ? 'alert-error' : 'alert-warning'

    content_tag :div, class: "alert #{warning_class} mt-2" do
      content_tag :div do
        if time_left < 1.hour
          'This invitation expires in less than 1 hour!'
        else
          "This invitation expires in #{time_ago_in_words(invitation.expires_at)}."
        end
      end
    end
  end

  def family_member_location_status(member)
    # This would integrate with location sharing when implemented
    content_tag :span, class: 'text-sm text-gray-500' do
      'Location sharing not implemented yet'
    end
  end

  def family_creation_benefits
    content_tag :div, class: 'bg-base-200 p-4 rounded-lg' do
      content_tag :h3, 'Family Features:', class: 'font-semibold mb-2' do
        concat content_tag(:h3, 'Family Features:', class: 'font-semibold mb-2')
        concat content_tag(:ul, class: 'list-disc list-inside space-y-1 text-sm') do
          concat content_tag(:li, "Share your current location with up to #{Family::MAX_MEMBERS - 1} family members")
          concat content_tag(:li, 'See where your family members are right now')
          concat content_tag(:li, 'Control your privacy with sharing toggles')
          concat content_tag(:li, 'Invite members by email')
          concat content_tag(:li, 'Secure and private - only family members can see your location')
        end
      end
    end
  end
end