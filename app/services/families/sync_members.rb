# frozen_string_literal: true

module Families
  class SyncMembers
    attr_reader :family

    def initialize(family:, notify: true)
      @family = family
      @notify = notify
    end

    def call
      return false if DawarichSettings.self_hosted?
      return false if family.blank?

      family.with_lock do
        refresh_access_until
        syncable_members.each { |member| granted? ? grant(member) : lapse(member) }
      end

      true
    end

    private

    def owner
      @owner ||= User.find_by(id: family.creator_id)
    end

    def refresh_access_until
      return unless owner&.family?
      return if owner.active_until.blank?

      family.update!(access_until: owner.active_until)
    end

    def granted?
      family.access_until&.future? || false
    end

    def syncable_members
      family.members.includes(:family_membership).reject do |member|
        member == owner || member.own_subscription_live?
      end
    end

    def grant(member)
      member.skip_family_sync = true
      member.update!(
        plan: :pro, status: :active, active_until: family.access_until, subscription_source: :none
      )
      Families::LapseNotice.clear(member)
    end

    def lapse(member)
      member.skip_family_sync = true
      member.update!(plan: :lite, status: :inactive, active_until: family.access_until)
      return if Families::LapseNotice.notified?(member)

      @notify ? Families::LapseNotificationJob.perform_later(member.id, family.id) : Families::LapseNotice.mark(member)
    end
  end
end
