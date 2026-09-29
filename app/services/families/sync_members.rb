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
        syncable_members.each do |member|
          next grant(member) if granted?

          lapsed = lapse(member)
          produce_lapse_notice(lapsed) if lapsed
        end
      end

      true
    end

    private

    def owner
      @owner ||= User.find_by(id: family.creator_id)
    end

    def refresh_access_until
      family.refresh_access_until!(owner)
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
      return nil if Families::LapseNotice.notified?(member)
      return Families::LapseNotice.mark(member) && nil unless @notify

      member
    end

    def produce_lapse_notice(member)
      lapse_at = family.access_until&.utc&.iso8601 || 'none'
      JobCommands.produce('mail.family_lapse', {
                            'user_id' => member.id,
                            'family_id' => family.id,
                            'locale' => I18n.locale.to_s,
                            'lapse_at' => lapse_at
                          }, aggregate_id: member.id, producer: 'Families::SyncMembers',
                             dedupe_key: "family-lapse:#{family.id}:#{member.id}:#{lapse_at}")
    end
  end
end
