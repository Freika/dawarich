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

  defp create(conn) do
    case IntegrationActions.admit(conn, ["POST"], ["job_name"]) do
      :ok ->
        case IntegrationCommands.enqueue(
               Repo,
               conn.assigns.current_user.id,
               conn.assigns.api_params["job_name"]
             ) do
          {:ok, :queued} ->
            message =
              Translate.t(
                IntegrationActions.locale(conn),
                "controllers.settings.background_jobs.job_was_successfully_created",
                %{}
              )

            IntegrationActions.redirect(conn, "/imports", %{"notice" => message})

          {:error, :not_owned} ->
            SettingsActions.reject(conn, 503)

          {:error, :enqueue_failed} ->
            SettingsActions.reject(conn, 500)

          {:error, _} ->
            SettingsActions.reject(conn, 422)
        end

      {:error, status} ->
        SettingsActions.reject(conn, status)
    end
  end
end
