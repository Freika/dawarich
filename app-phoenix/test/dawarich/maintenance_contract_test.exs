defmodule Dawarich.MaintenanceContractTest do
  use Dawarich.ScratchCase

  alias Dawarich.{RailsTree, ReleaseMigrator}
  alias Dawarich.Families.{InvitationCleanupWorker, LocationRequestExpiryWorker}
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.Users.PointsCounterCorrectionWorker

  @entries [
    {InvitationCleanupWorker, "nightly_family_invitations_cleanup_job",
     "Family::Invitations::CleanupJob", "app/jobs/family/invitations/cleanup_job.rb"},
    {LocationRequestExpiryWorker, "family_location_requests_expiry_job",
     "Families::ExpireLocationRequestsJob", "app/jobs/families/expire_location_requests_job.rb"},
    {PointsCounterCorrectionWorker, "points_counter_correction_job",
     "Users::PointsCounterCorrectionJob", "app/jobs/users/points_counter_correction_job.rb"}
  ]

  test "each wave-1 cron entry is registered and mirrors config/schedule.yml and its gated Rails class" do
    schedule = RailsTree.read("config/schedule.yml")

    for {worker, name, class, path} <- @entries do
      key = "cron:" <> name
      assert worker.key() == key
      assert worker.new(%{}).changes.queue == "maintenance"

      [_, expression, ^class] =
        Regex.run(~r/^#{name}:\n\s+cron: "([^"]+)"[^\n]*\n\s+class: "([^"]+)"/m, schedule)

      assert %{kind: :cron, expression: ^expression, worker: ^worker, claimable: false} =
               Enum.find(Registry.entries(), &(&1.key == key))

      source = RailsTree.read(path)
      assert source =~ "OWNERSHIP_KEY = '#{key}'"
      assert source =~ "JobOwnership.with_owner(OWNERSHIP_KEY)"
    end
  end

  test "wave 1 ships unclaimable: the boot claimer takes none of its keys" do
    assert Registry.claimable() == []
  end

  test "the Rails enums and scope hold the values the sweeps write and match" do
    assert RailsTree.read("app/models/family/invitation.rb") =~
             "enum :status, { pending: 0, accepted: 1, expired: 2, cancelled: 3 }"

    assert RailsTree.read("app/models/family/location_request.rb") =~
             "enum :status, { pending: 0, accepted: 1, declined: 2, expired: 3 }"

    user = RailsTree.read("app/models/user.rb")
    assert user =~ "enum :status, { inactive: 0, active: 1, trial: 2, pending_payment: 3 }"
    assert user =~ "scope :active_or_trial, -> { where(status: %i[active trial]) }"
  end

  test "the three sweeps run against the real Rails schema" do
    assert {:ok, _} = ReleaseMigrator.migrate(ScratchRepo)
    for {worker, _, _, _} <- @entries, do: Ownership.put!(ScratchRepo, worker.key(), :oban)

    assert InvitationCleanupWorker.run(ScratchRepo, ~N[2026-09-26 12:00:00]) == :ok
    assert LocationRequestExpiryWorker.run(ScratchRepo, ~N[2026-09-26 12:00:00]) == :ok
    assert PointsCounterCorrectionWorker.run(ScratchRepo, 1000) == :ok
  end
end
