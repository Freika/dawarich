defmodule Dawarich.Digests.Failure do
  @moduledoc false

  alias Dawarich.{I18n, Notifications}
  alias Dawarich.Mail.ExploreFeatures

  def create!(repo, kind, user_id, error, stack) do
    case repo.query!(
           "SELECT settings FROM public.users WHERE id=$1 AND deleted_at IS NULL",
           [user_id],
           log: false
         ).rows do
      [] ->
        :missing

      [[settings]] ->
        locale = ExploreFeatures.locale(settings, nil)
        prefix = "jobs.users.digests.#{kind}.calculating_job."
        title = title(locale, kind, prefix)
        backtrace = stack |> lines() |> Enum.take(20) |> Enum.join("\n")

        {:ok, content} =
          I18n.t(locale, prefix <> "message_stacktrace_backtrace", %{
            "message" => message(error),
            "backtrace" => backtrace
          })

        Notifications.create!(repo, user_id, :error, title, content)
    end
  end

  defp title(locale, kind, prefix) when kind in [:monthly, "monthly"] do
    {:ok, title} = I18n.t(locale, prefix <> "monthly_digest_calculation_failed")
    title
  end

  defp title(locale, _kind, prefix) do
    {:ok, period} = I18n.t(locale, prefix <> "year_end_digest")

    {:ok, title} =
      I18n.t(locale, prefix <> "period_label_calculation_failed", %{"period_label" => period})

    title
  end

  defp lines(nil), do: []

  defp lines(stack) do
    if Enum.all?(stack, &is_binary/1),
      do: stack,
      else: stack |> Exception.format_stacktrace() |> String.split("\n", trim: true)
  end

  defp message(%{__exception__: true} = error), do: Exception.message(error)
  defp message({kind, reason}), do: Exception.format_banner(kind, reason)
  defp message(reason), do: inspect(reason)
end
