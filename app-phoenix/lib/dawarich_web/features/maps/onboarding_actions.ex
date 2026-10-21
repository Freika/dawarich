defmodule DawarichWeb.OnboardingActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Settings.Onboarding}
  alias DawarichWeb.SettingsActions

  def init(action), do: action

  def call(conn, :update) do
    case SettingsActions.admit(conn, ~w(PATCH PUT)) do
      :ok ->
        case Onboarding.complete(Repo, conn.assigns.current_user.id) do
          {:ok, :ok} -> conn |> send_resp(200, "") |> halt()
          {:error, _} -> SettingsActions.reject(conn, 500)
        end

      {:error, status} ->
        SettingsActions.reject(conn, status)
    end
  end
end
