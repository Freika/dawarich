defmodule DawarichWeb.IntegrationJobActions do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, Imports.IntegrationCommands}
  alias DawarichWeb.{IntegrationActions, SettingsActions, Translate}

  def init(action), do: action

  def enabled?(conn, params) do
    if legacy_settings?(conn),
      do: DawarichWeb.AdminWritesGate.background?(conn, params),
      else: IntegrationActions.enabled?(conn, params)
  end

  def call(conn, :create) do
    if legacy_settings?(conn) do
      DawarichWeb.AdminWrites.Settings.call(conn, action: :background)
    else
      conn =
        if Map.has_key?(conn.assigns, :api_params),
          do: conn,
          else: DawarichWeb.Api.Body.call(conn, nested_form: "settings")

      if conn.halted, do: conn, else: create(conn)
    end
  end

  defp legacy_settings?(conn) do
    params = URI.decode_query(conn.query_string)

    Map.has_key?(params, "settings[visits_suggestions_enabled]") and
      not Map.has_key?(params, "job_name")
  rescue
    ArgumentError -> false
  end

  defp destination("start_airtrail_import"), do: "/settings/integrations"
  defp destination("start_teslamate_sync"), do: "/settings/integrations?service=teslamate"

  defp destination(name) when name in ~w(start_reverse_geocoding continue_reverse_geocoding),
    do: "/settings/background_jobs"

  defp destination(_), do: "/imports"

  defp create(conn) do
    case IntegrationActions.admit(conn, ["POST"], ["job_name"]) do
      :ok -> admitted(conn)
      {:error, status} -> SettingsActions.reject(conn, status)
    end
  end

  defp admitted(conn) do
    if conn.assigns.api_params["job_name"] in ~w(start_reverse_geocoding continue_reverse_geocoding) and
         not IntegrationActions.hosted?(conn) do
      IntegrationActions.redirect(
        conn,
        "/",
        %{
          "alert" =>
            Translate.t(
              IntegrationActions.locale(conn),
              "controllers.application.you_are_not_authorized_to_perform_this_action",
              %{}
            )
        },
        303
      )
    else
      enqueue(conn)
    end
  end

  defp enqueue(conn) do
    case IntegrationCommands.enqueue(
           Repo,
           conn.assigns.current_user.id,
           conn.assigns.api_params["job_name"],
           locale: IntegrationActions.locale(conn),
           self_hosted: IntegrationActions.hosted?(conn)
         ) do
      {:ok, :queued} ->
        message =
          Translate.t(
            IntegrationActions.locale(conn),
            "controllers.settings.background_jobs.job_was_successfully_created",
            %{}
          )

        IntegrationActions.redirect(conn, destination(conn.assigns.api_params["job_name"]), %{
          "notice" => message
        })

      {:error, :not_owned} ->
        SettingsActions.reject(conn, 503)

      {:error, :enqueue_failed} ->
        SettingsActions.reject(conn, 500)

      {:error, _} ->
        SettingsActions.reject(conn, 422)
    end
  end
end
