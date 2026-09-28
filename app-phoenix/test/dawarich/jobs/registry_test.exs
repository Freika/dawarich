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
