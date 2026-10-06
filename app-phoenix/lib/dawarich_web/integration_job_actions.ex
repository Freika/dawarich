defmodule DawarichWeb.IntegrationJobActions do
  @moduledoc false
  @behaviour Plug
  alias Dawarich.{Repo, Imports.IntegrationCommands}
  alias DawarichWeb.{IntegrationActions, SettingsActions, Translate}

  def init(action), do: action

  def call(conn, :create) do
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
