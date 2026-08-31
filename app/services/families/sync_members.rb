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

      refresh_access_until
      syncable_members.each { |member| granted? ? grant(member) : lapse(member) }

      true
    end

    private

    def owner
      @owner ||= User.find_by(id: family.creator_id)
    end

    def refresh_access_until
      return unless owner&.family?

      family.update!(access_until: owner.active_until)
    end

    def granted?
      family.access_until&.future? || false
    end

    def syncable_members
      family.members.includes(:family_membership).reject do |member|
        member == owner || !member.sub_source_none?
      end
    end

    def grant(member)
      member.update!(plan: :pro, status: :active, active_until: family.access_until)
      Families::LapseNotice.clear(member)
    end

    def lapse(member)
      member.update!(status: :inactive, active_until: lapsed_until)
      return if Families::LapseNotice.notified?(member)

      @notify ? Families::LapseNotificationJob.perform_later(member.id, family.id) : Families::LapseNotice.mark(member)
    end

    def lapsed_until
      [family.access_until, Time.current].compact.min
    end
  end
end
