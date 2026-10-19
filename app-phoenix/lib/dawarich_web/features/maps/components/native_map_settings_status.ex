defmodule DawarichWeb.NativeMapSettingsStatus do
  @moduledoc false
  use Phoenix.Component
  import DawarichWeb.Translate, only: [t: 3]

  attr :settings, :map, default: nil
  attr :locale, :string, required: true

  def status(assigns) do
    ~H"""
    <p
      :if={@settings && @settings.error}
      class="alert alert-error text-sm [overflow-wrap:anywhere]"
      role="alert"
    >
      {error(@locale, @settings.error)}
    </p>
    <p
      :if={@settings && @settings[:notice]}
      id="native-settings-notice"
      class="alert alert-success text-sm"
      role="status"
    >
      {notice(@locale, @settings.notice)}
    </p>
    """
  end

  defp error(_locale, message) when is_binary(message), do: message

  defp error(locale, {:recalculation, :in_progress}),
    do:
      t(
        locale,
        "controllers.api.v1.recalculations.recalculation_already_in_progress_for_this_user",
        %{}
      )

  defp error(locale, {:anomalies, :in_progress}),
    do: t(locale, "controllers.api.v1.points.anomaly_re_evaluation_already_in_progress", %{})

  defp error(locale, {:recalculation, _}),
    do: t(locale, "javascript.messages.could_not_queue_recalculation_please_try_again", %{})

  defp error(locale, {:anomalies, _}),
    do: t(locale, "javascript.messages.could_not_queue_re_evaluation_please_try_again", %{})

  defp error(locale, :reclassify),
    do: t(locale, "javascript.messages.failed_to_update_settings", %{})

  defp error(locale, _reason), do: t(locale, "javascript.messages.failed_to_update_settings", %{})

  defp notice(locale, {:live, enabled}),
    do: t(locale, "javascript.live_map." <> if(enabled, do: "enabled", else: "disabled"), %{})

  defp notice(locale, :recalculation),
    do: t(locale, "javascript.settings.recalculation_queued", %{})

  defp notice(locale, :reclassify),
    do:
      t(
        locale,
        "controllers.tracks.recalculations.re_classification_started_your_tracks_will_update_over_the_next",
        %{}
      )

  defp notice(locale, :anomalies), do: t(locale, "javascript.settings.re_evaluation_queued", %{})
end
