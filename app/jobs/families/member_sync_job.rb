# frozen_string_literal: true

class Families::MemberSyncJob < ApplicationJob
  queue_as :families

  def perform(family_id)
    Families::JobCommands.execute('member_sync', family_id, job_id: job_id) do
      family = Family.find_by(id: family_id)
      Families::SyncMembers.new(family: family).call if family
    end
  end
end
