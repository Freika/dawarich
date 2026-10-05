defmodule Dawarich.Users.RecalculationNotifications do
  @moduledoc false

  alias Dawarich.{I18n, Notifications}
  alias Dawarich.Mail.ExploreFeatures
  @prefix "jobs.users.recalculate_data_job."

  def create!(repo, args, outcome, detail) do
    if Map.get(args, "notify", true) not in [false, nil] do
      case repo.query!(
             "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL",
             [args["user_id"]],
             log: false
           ).rows do
        [] ->
          :missing

        [[settings]] ->
          locale = ExploreFeatures.locale(settings, nil)
          {kind, title, content} = message(locale, outcome, detail)
          Notifications.create!(repo, args["user_id"], kind, title, content)
      end
    end
  end

  defp message(locale, :success, years) do
    label =
      if length(years) == 1,
        do: to_string(hd(years)),
        else: t(locale, "year_count", %{"count" => length(years)})

    {:info, t(locale, "data_recalculation_completed"),
     t(locale, "stats_tracks_and_digests_have_been_recalculated_for_year_label", %{
       "year_label" => label
     })}
  end

  defp message(locale, :busy, _) do
    {:warning, t(locale, "data_recalculation_busy"),
     t(locale, "another_recalculation_is_already_running_please_try_again_in_a")}
  end

  defp message(locale, :error, {error, stack}) do
    frames =
      if Enum.all?(stack, &is_binary/1),
        do: stack,
        else: Exception.format_stacktrace(stack) |> String.split("\n", trim: true)

    {:error, t(locale, "data_recalculation_failed"),
     t(locale, "message_stacktrace_n", %{
       "message" => Exception.message(error),
       "backtrace" => Enum.take(frames, 10) |> Enum.join("\n")
     })}
  end

  defp t(locale, key, values \\ %{}) do
    {:ok, value} = I18n.t(locale, @prefix <> key, values)
    value
  end
end
