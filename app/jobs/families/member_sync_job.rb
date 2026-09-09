# frozen_string_literal: true

class Families::MemberSyncJob < ApplicationJob
  queue_as :families

  def perform(family_id)
    family = Family.find_by(id: family_id)

    return unless family

    Families::SyncMembers.new(family: family).call
  end
end
