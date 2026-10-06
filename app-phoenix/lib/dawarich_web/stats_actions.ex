defmodule DawarichWeb.StatsActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Stats.WebCommands}
  alias DawarichWeb.{RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  def init(action), do: action

  def call(conn, action) do
    user = conn.assigns.current_user
    context = %{now: conn.assigns[:now] || DateTime.utc_now(), locale: conn.assigns.locale}

    if active?(user, context.now) do
      result =
        if action == :update_all,
          do: WebCommands.update_all(Repo, user, context),
          else:
            WebCommands.update(
              Repo,
              user,
              conn.path_params["year"],
              conn.path_params["month"],
              context
            )

      case result do
        {:ok, result} -> redirect(conn, result)
        {:replay, reason} -> Body.replay(conn, reason)
        {:error, _} -> conn |> send_resp(500, "") |> halt()
      end
    else
      inactive(conn, context.locale)
    end
  end

  def active?(%{active_until: %DateTime{} = until}, now),
    do: DateTime.compare(until, now) == :gt

  def active?(%{active_until: %NaiveDateTime{} = until}, now),
    do: NaiveDateTime.compare(until, DateTime.to_naive(now)) == :gt

  def active?(_, _), do: false

  def inactive(conn, locale),
    do:
      redirect(conn, %{
        status: 303,
        path: "/",
        flash: :notice,
        message: Translate.t(locale, "controllers.application.your_account_is_not_active", %{})
      })

  def redirect(conn, result) do
    conn
    |> RailsSession.stage(%{
      "flash" => %{
        "discard" => [],
        "flashes" => %{Atom.to_string(result.flash) => result.message}
      }
    })
    |> put_resp_header("location", RequestURL.base(conn) <> result.path)
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_content_type("text/html")
    |> send_resp(result.status, "")
    |> halt()
  end
end
