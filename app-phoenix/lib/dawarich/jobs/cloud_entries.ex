defmodule Dawarich.Jobs.CloudEntries do
  @moduledoc false

  @commands [
    {"users.creation_webhook", Dawarich.Users.CreationWebhookWorker},
    {"users.destruction_webhook", Dawarich.Users.DestructionWebhookWorker},
    {"partnero.customer_signup", Dawarich.Partnero.CustomerSignupWorker},
    {"release.family_backfill", Dawarich.ReleaseJobs.FamilyBackfill}
  ]

  def entries do
    for {command, worker} <- @commands,
        do: %{key: "command:" <> command, kind: :command, worker: worker, claimable: false}
  end
end
