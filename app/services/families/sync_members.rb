# frozen_string_literal: true

module Families
  class SyncMembers
    NOTIFIED_AT_KEY = 'plan_lapse_notified_at'

    attr_reader :family

    def initialize(family:)
      @family = family
    end

    def call
      return false if DawarichSettings.self_hosted?
      return false if family.blank?

      syncable_members.each { |member| granted? ? grant(member) : lapse(member) }

      true
    end

    private

    def owner
      @owner ||= family.owner
    end

    def granted?
      return false unless owner&.family?

      owner.active_until&.future? || false
    end

    def syncable_members
      family.members.includes(:family_membership).reject do |member|
        member == owner || !member.sub_source_none?
      end
    end

    def grant(member)
      member.update!(plan: :pro, status: :active, active_until: owner.active_until)
      clear_lapse_notice(member)
    end

    def lapse(member)
      member.update!(status: :inactive, active_until: owner&.active_until)
      return if lapse_notified?(member)

      FamilyMailer.plan_lapsed(member, family).deliver_later
      mark_lapse_notified(member)
    end

    def lapse_notified?(member)
      member.settings.dig('family', NOTIFIED_AT_KEY).present?
    end

    def mark_lapse_notified(member)
      write_family_setting(member, NOTIFIED_AT_KEY, Time.current.iso8601)
    end

    def clear_lapse_notice(member)
      return unless lapse_notified?(member)

      write_family_setting(member, NOTIFIED_AT_KEY, nil)
    end

    def write_family_setting(member, key, value)
      settings = member.settings || {}
      settings['family'] ||= {}

      value.nil? ? settings['family'].delete(key) : settings['family'][key] = value

      member.update!(settings: settings)
    end
  end
end
