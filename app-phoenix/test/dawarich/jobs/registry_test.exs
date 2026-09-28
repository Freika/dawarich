defmodule Dawarich.Jobs.RegistryTest do
  use ExUnit.Case, async: true

  alias Dawarich.Jobs.Registry

  test "release N claims nothing: every entry ships unclaimable" do
    assert Registry.claimable() == []
  end

  test "every key is namespaced, every cron entry has an expression and every worker exists" do
    for entry <- Registry.entries() do
      assert entry.key =~ ~r/\A(cron|command):[a-z0-9_.]+\z/
      assert Code.ensure_loaded?(entry.worker)
      if entry.kind == :cron, do: assert(is_binary(entry.expression))

      if entry.kind == :command,
        do: assert(function_exported?(entry.worker, :args_from_command, 2))
    end
  end

  test "catch_up is a boolean and appears only on cron entries" do
    for e <- Registry.entries(),
        Map.has_key?(e, :catch_up),
        do: assert(e.kind == :cron and is_boolean(e.catch_up))
  end

  test "registry lists the seven wave-2 commands and the Lite cron, all unclaimable" do
    wave2 = %{
      "command:exports.points" => Dawarich.Exports.PointsWorker,
      "command:mail.family_invitation" => Dawarich.Mail.FamilyInvitationWorker,
      "command:mail.family_lapse" => Dawarich.Mail.FamilyLapseWorker,
      "command:mail.user.welcome" => Dawarich.Mail.WelcomeWorker,
      "command:mail.user.archival_approaching" => Dawarich.Mail.ArchivalApproachingWorker,
      "command:mail.user.oauth_account_link" => Dawarich.Mail.OauthAccountLinkWorker,
      "command:mail.user.account_destroy_confirmation" =>
        Dawarich.Mail.AccountDestroyConfirmationWorker,
      "cron:lite_archival_warning_job" => Dawarich.Lite.ArchivalWarningWorker
    }

    entries = Map.new(Registry.entries(), &{&1.key, &1})

    for {"command:" <> _ = key, worker} <- wave2 do
      assert %{kind: :command, worker: ^worker, claimable: false} = entries[key], key
    end

    assert %{kind: :cron, worker: Dawarich.Lite.ArchivalWarningWorker, claimable: false} =
             entries["cron:lite_archival_warning_job"]

    assert Dawarich.Lite.ArchivalWarningWorker.key() == "cron:lite_archival_warning_job"
  end

  test "commands resolve by type and unknown types do not" do
    for %{kind: :command, key: "command:" <> type, worker: worker} <- Registry.entries() do
      assert Registry.command(type) == {:ok, worker}
    end

    assert Registry.command("nope") == :error
  end

  test "the app-version cron has one source: the registry matches config/schedule.yml" do
    schedule = File.read!(Path.expand("../../../../config/schedule.yml", __DIR__))
    [_, expression] = Regex.run(~r/app_version_checking_job:\n\s+cron: "([^"]+)"/, schedule)

    assert {expression, Dawarich.AppVersion.CheckWorker} in Registry.crontab()
  end
end
