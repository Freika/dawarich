defmodule Dawarich.Visits.RedetectNotifications do
  @moduledoc false

  alias Dawarich.Mail.ExploreFeatures
  alias Dawarich.{I18n, Notifications}
  alias Dawarich.Visits.Settings

  @scope "jobs.visits.full_history_redetect_job."

  def busy(repo, user_id) do
    locale = locale(repo, user_id)

    Notifications.create!(
      repo,
      user_id,
      :warning,
      t!(locale, "visit_re_detection_busy"),
      t!(locale, "another_re_detection_is_already_running_try_again_in_a")
    )
  end

  def no_points(repo, user_id) do
    locale = locale(repo, user_id)

    Notifications.create!(
      repo,
      user_id,
      :info,
      t!(locale, "visit_re_detection"),
      t!(locale, "no_points_to_re_detect")
    )
  end

  def complete(repo, user_id, visits, months) do
    locale = locale(repo, user_id)

    content =
      t!(locale, "visits_created_visits_across_size_months", %{
        "visits" => t!(locale, "visits_count", %{"count" => visits}),
        "months" => t!(locale, "months_count", %{"count" => months})
      })

    Notifications.create!(
      repo,
      user_id,
      :info,
      t!(locale, "visit_re_detection_complete"),
      content
    )
  end

  def partial(repo, user_id, visits, ok_months, months, failed) do
    locale = locale(repo, user_id)

    content =
      t!(locale, "visits_created_visits_across_ok_months_of_size_months_size", %{
        "visits" => t!(locale, "visits_count", %{"count" => visits}),
        "ok_months" => t!(locale, "months_count", %{"count" => ok_months}),
        "months" => t!(locale, "months_count", %{"count" => months}),
        "count" => failed
      })

    Notifications.create!(
      repo,
      user_id,
      :warning,
      t!(locale, "visit_re_detection_partially_complete"),
      content
    )
  end

  def failed(repo, user_id, exception) do
    locale = locale(repo, user_id)

    Notifications.create!(
      repo,
      user_id,
      :error,
      t!(locale, "visit_re_detection_failed"),
      Exception.message(exception)
    )
  end

  defp locale(repo, user_id) do
    case Settings.load(repo, user_id) do
      %{settings: settings} -> ExploreFeatures.locale(settings, nil)
      nil -> "en"
    end
  end

  defp t!(locale, key, bindings \\ %{}) do
    {:ok, text} = I18n.t(locale, @scope <> key, bindings)
    text
  end
end
