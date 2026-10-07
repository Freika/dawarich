defmodule DawarichWeb.DigestActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Digests.WebCommands}
  alias DawarichWeb.{StatsActions, LayoutAssigns}
  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, action) do
    user = conn.assigns.current_user

    context = %{
      now: conn.assigns[:now] || DateTime.utc_now(),
      locale: conn.assigns.locale,
      self_hosted: LayoutAssigns.self_hosted?()
    }

    if action == :create and not StatsActions.active?(user, context.now) do
      StatsActions.inactive(conn, context.locale)
    else
      result =
        case action do
          :create -> WebCommands.create(Repo, user, conn.assigns.api_params["year"], context)
          :destroy -> WebCommands.destroy(Repo, user, conn.path_params["year"], context)
        end

      case result do
        {:ok, result} -> StatsActions.redirect(conn, result)
        {:replay, reason} -> Body.replay(conn, reason)
        {:error, _} -> conn |> send_resp(500, "") |> halt()
      end
    end
  end
end
