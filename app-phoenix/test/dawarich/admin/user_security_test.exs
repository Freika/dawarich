defmodule Dawarich.Admin.UserSecurityTest do
  use ExUnit.Case, async: false
  alias Dawarich.Admin.UserSecurity
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.RailsUser
  @now ~U[2026-10-04 10:00:00.000000Z]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 15301,
      email: "a10b-security-admin@example.invalid",
      admin: true,
      api_key: "synthetic-actor-key",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    RailsUser.insert!(%{
      id: 15302,
      email: "a10b-security-target@example.invalid",
      api_key: "synthetic-target-key",
      settings: %{"immich_url" => "https://immich.example.invalid///"}
    })

    %{
      actor: Accounts.get(15301),
      context: %{self_hosted: true, oidc: false, locale: "en", clock: fn -> @now end}
    }
  end

  test "rotates the selected target key without changing actor credentials", c do
    assert Code.ensure_loaded?(UserSecurity), "target security actions must exist"
    before = snapshot(15301)
    target_before = snapshot(15302)
    assert {:ok, 15302} = UserSecurity.rotate(c.actor, 15302, c.context)
    target = snapshot(15302)

    key_valid =
      is_binary(target["api_key"]) and target["api_key"] =~ ~r/\A[0-9a-f]{64}\z/ and
        target["api_key"] != target_before["api_key"]

    assert key_valid
    assert target["settings"] == %{"immich_url" => "https://immich.example.invalid"}
    assert target["updated_at"] == "2026-10-04T10:00:00"
    actor_unchanged = snapshot(15301) == before
    assert actor_unchanged
    session = RailsUser.session(c.actor.id)
    raw = URI.encode_query(%{"authenticity_token" => DawarichWeb.RailsCsrf.masked_token(session)})

    conn =
      Plug.Test.conn("POST", "/settings/users/15302/regenerate_api_key", raw)
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(raw)))
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> DawarichWeb.AdminWrites.Users.call(action: :rotate, context: c.context)

    assert conn.status == 302 and conn.halted

    assert Plug.Conn.get_resp_header(conn, "location") == [
             "http://www.example.com/settings/users/15302"
           ]

    assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"] ==
             "API key has been regenerated."

    for field <-
          ~w(encrypted_password email admin status reset_password_token reset_password_sent_at) do
      same = target[field] == target_before[field]
      assert same
    end

    assert {:handoff, :target} = UserSecurity.rotate(c.actor, -1, c.context)

    Repo.query!("UPDATE users SET deleted_at=$1 WHERE id=15302", [DateTime.to_naive(@now)],
      log: false
    )

    before = snapshot(15302)
    assert {:handoff, :target} = UserSecurity.rotate(c.actor, 15302, c.context)
    assert snapshot(15302) == before

    Repo.query!(
      "UPDATE users SET deleted_at=NULL,settings=$1 WHERE id=15302",
      [%{"maps" => %{"url" => 5}}],
      log: false
    )

    before = snapshot(15302)
    assert {:handoff, :settings_callback} = UserSecurity.rotate(c.actor, 15302, c.context)
    assert snapshot(15302) == before
    Repo.query!("UPDATE users SET admin=false WHERE id=15301", [], log: false)
    assert {:handoff, :actor} = UserSecurity.rotate(c.actor, 15302, c.context)
  end

  test "issues targeted reset with existing digest and sealed mail or falls back before effects",
       c do
    assert Code.ensure_loaded?(UserSecurity), "target security actions must exist"

    for context <- [c.context, Map.put(c.context, :mail_deliverable, false)] do
      before = {snapshot(15301), snapshot(15302), jobs()}
      assert {:handoff, :synchronous_mail} = UserSecurity.reset(c.actor, 15302, context)
      unchanged = {snapshot(15301), snapshot(15302), jobs()} == before
      assert unchanged
    end

    assert {:handoff, :synchronous_mail} = UserSecurity.reset(c.actor, -1, c.context)

    source =
      File.read!("test/fixtures/admin_mutations/reset_mail_failure.json") |> Jason.decode!()

    assert source["after"]["reset_token_present"]
    assert source["error"] == "RuntimeError"
  end

  defp snapshot(id) do
    [[row]] = Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [id], log: false).rows
    row
  end

  defp jobs do
    Repo.query!(
      "SELECT (SELECT count(*) FROM job_outbox),(SELECT count(*) FROM oban.oban_jobs)",
      [],
      log: false
    ).rows
  end
end
