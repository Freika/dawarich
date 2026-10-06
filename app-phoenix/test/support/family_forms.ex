defmodule Dawarich.Test.FamilyForms do
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{FrameSeeds, RailsUser}
  alias DawarichWeb.{RailsCsrf, FamilyFormRoutes}

  def seed do
    Code.ensure_loaded!(Dawarich.Accounts.User)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    owner = FrameSeeds.seed_family!(FrameSeeds.load_family("owner_en"))
    %{owner: owner, member: Accounts.get(90102), outsider: Accounts.get(90103)}
  end

  def request(user, method, path, params \\ %{}, headers \\ []) do
    session = if user, do: RailsUser.session(user.id), else: %{}
    params = Map.put_new(params, "authenticity_token", RailsCsrf.masked_token(session))

    conn =
      Plug.Test.conn(method, path, Plug.Conn.Query.encode(params))
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
      |> assign(:now, ~U[2026-10-03 10:00:00Z])

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    FamilyFormRoutes.call(conn, FamilyFormRoutes.init([]))
  end

  def json_request(user, method, path, params) do
    session = RailsUser.session(user.id)

    Plug.Test.conn(method, path, Jason.encode!(params))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json")
    |> put_req_header("x-csrf-token", RailsCsrf.masked_token(session))
    |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
    |> assign(:now, ~U[2026-10-03 10:00:00Z])
    |> FamilyFormRoutes.call(FamilyFormRoutes.init([]))
  end

  def records(sql, args \\ []), do: Repo.query!(sql, args).rows
end
