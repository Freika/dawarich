defmodule Dawarich.UserData.Restore.Messages do
  @moduledoc false
  alias Dawarich.UserData.Restore
  alias Dawarich.Imports.Fence
  require Logger
  @summary ~w(points visits places trips areas tags tracks digests imports exports stats)

  def success(repo, user, stats, context) do
    summary =
      Enum.map_join(@summary, ", ", &"#{stats[&1 <> "_created"]} #{&1}") <>
        ", #{stats["files_restored"]} files restored, #{stats["notifications_created"]} notifications"

    notify(
      repo,
      user,
      :info,
      "data_import_completed",
      "your_data_has_been_imported_successfully_summary",
      %{"summary" => summary},
      context
    )
  end

  def failure(repo, user, error, context) do
    notify(
      repo,
      user,
      :error,
      "data_import_failed",
      "your_data_import_failed_with_error_message_please_check_the",
      %{"message" => Exception.message(error)},
      context
    )
  end

  def completeness(stats, expected) when is_map(expected) do
    for {name, count} <- expected, is_number(count), (stats[name <> "_created"] || 0) < count do
      actual = stats[name <> "_created"] || 0

      Logger.warning(
        "Import discrepancy - #{name}: expected #{count}, got #{actual} (#{count - actual} missing)"
      )
    end

    :ok
  end

  def completeness(_, _), do: :ok

  defp notify(repo, user, kind, title, content, vars, context) do
    Fence.run(context, fn ->
      locale = Restore.locale(repo, user, context)
      {:ok, title} = Dawarich.I18n.t(locale, "services.users.import_data." <> title)
      {:ok, content} = Dawarich.I18n.t(locale, "services.users.import_data." <> content, vars)
      Dawarich.Notifications.create!(repo, user, kind, title, content, context.now)
    end)
  end
end
