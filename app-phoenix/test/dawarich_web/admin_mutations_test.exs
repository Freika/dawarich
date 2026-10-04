defmodule DawarichWeb.AdminMutationsTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.AdminWrites.Users
  alias DawarichWeb.RailsCsrf

  defmodule RaceRepo do
    defdelegate transaction(fun), to: Dawarich.Repo
    defdelegate rollback(reason), to: Dawarich.Repo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "SELECT EXISTS(SELECT 1 FROM users WHERE email="),
        do: %{rows: [[false]]},
        else: Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15011,
      email: "a10b-http-admin@example.invalid",
      admin: true,
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15012,
      email: "a10b-http-collision@example.invalid",
      deleted_at: ~N[2026-10-04 10:00:00]
    })

    %{
      session: RailsUser.session(15011),
      opts: [
        context: %{
          self_hosted: true,
          oidc: false,
          clock: fn -> ~U[2026-10-04 10:00:00.000000Z] end
        }
      ]
    }
  end

  test "returns Rails create validation failure without a row or effects", c do
    assert Code.ensure_loaded?(Users), "admin users plug must exist"

    for {name, email, password} <- [
          {"duplicate_en", "a10b-http-collision@example.invalid", "a10b-create-password"},
          {"invalid_email", "invalid", "a10b-create-password"},
          {"short_password", "a10b-http-new@example.invalid", "short"}
        ] do
      before = snapshot()
      conn = request(c.session, email, password) |> Users.call(c.opts)
      oracle = File.read!("test/fixtures/admin_mutations/#{name}.json") |> Jason.decode!()
      assert conn.status == 303 and conn.halted and conn.resp_body == ""
      assert get_resp_header(conn, "location") == ["http://www.example.com/settings/users"]
      message = conn.private.dawarich_rails_session_changes["flash"]["flashes"]["alert"]
      assert message == oracle["flash"]["alert"]
      assert snapshot() == before
    end

    conn =
      request(c.session, "a10b-http-created@example.invalid", "a10b-create-password")
      |> Users.call(c.opts)

    assert conn.status == 302 and conn.halted

    assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"] ==
             "User was successfully created"

    assert Repo.query!(
             "SELECT count(*) FROM users WHERE email=$1",
             ["a10b-http-created@example.invalid"],
             log: false
           ).rows == [[1]]

    refute Map.has_key?(conn.private.dawarich_rails_session_changes, "warden.user.user.key")

    before = snapshot()
    race_opts = [context: Map.put(c.opts[:context], :repo, RaceRepo)]

    conn =
      request(c.session, "a10b-http-collision@example.invalid", "a10b-create-password")
      |> Users.call(race_opts)

    assert conn.status == 500 and conn.halted and conn.resp_body == ""
    assert snapshot() == before
  end

  defp request(session, email, password) do
    raw =
      URI.encode_query(%{
        "authenticity_token" => RailsCsrf.masked_token(session),
        "user[email]" => email,
        "user[password]" => password,
        "user[admin]" => "1"
      })

    Plug.Test.conn("POST", "/settings/users", raw)
    |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("accept", "text/html")
  end

  defp snapshot do
    Repo.query!(
      "SELECT (SELECT count(*) FROM users),(SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end
end
