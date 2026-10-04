defmodule Dawarich.Auth.ApiKeysTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.ApiKeys
  alias Dawarich.Test.RailsUser

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    hash = Bcrypt.hash_pwd_salt("a11rest-key-password-42", log_rounds: 4)

    for id <- [73901, 73902] do
      RailsUser.insert!(%{
        id: id,
        email: "a11rest-key-#{id}@dawarich.test",
        encrypted_password: hash,
        api_key: "A11REST_OLD_KEY_#{id}",
        settings: %{"timezone" => "Europe/Berlin", "onboarding_completed" => true}
      })

      Repo.query!(
        "UPDATE users SET reset_password_token='a11rest-key-reset-'||id::text,reset_password_sent_at=now(),sign_in_count=7,failed_attempts=2,failed_otp_attempts=3,remember_created_at=now(),updated_at=now()-interval '1 day' WHERE id=$1",
        [id]
      )
    end

    %{salt: binary_part(hash, 0, 29), context: %{self_hosted: true, oidc: false}}
  end

  test "rotation retires the old key across both lookup forms without other effects", c do
    assert Code.ensure_loaded?(ApiKeys), "API key lifecycle module must exist"

    oracle =
      File.read!("test/fixtures/auth/account/api_keys.json")
      |> Jason.decode!()
      |> Enum.find(&(&1["name"] == "plain"))

    before = snapshot(73901)
    other = snapshot(73902)
    effects = effects()
    for form <- [:query, :bearer], do: assert(lookup(before["api_key"], form) == {200, 73901})
    assert {:ok, actor} = ApiKeys.rotate(73901, c.salt, c.context)
    assert actor.id == 73901
    after_row = snapshot(73901)
    key = after_row["api_key"]
    assert is_binary(key) and Regex.match?(~r/\A[0-9a-f]{64}\z/, key)
    assert key != before["api_key"] and key != other["api_key"]
    assert changed(before, after_row) == oracle["changed"]
    assert same?(snapshot(73902), other)
    assert effects() == effects

    for form <- [:query, :bearer] do
      assert lookup(before["api_key"], form) == {401, nil}
      assert lookup(key, form) == {200, 73901}
      assert lookup(other["api_key"], form) == {200, 73902}
    end

    keys =
      for _ <- 1..8 do
        assert {:ok, _} = ApiKeys.rotate(73901, c.salt, c.context)
        snapshot(73901)["api_key"]
      end

    assert length(Enum.uniq([key | keys])) == 9
    assert effects() == effects
    assert same?(snapshot(73902), other)

    for sql <- [
          "email=''",
          "provider='github'",
          "otp_required_for_login=true",
          "status=3",
          "locked_at=now()",
          "deleted_at=now()",
          "settings='{\"immich_url\":\"https://immich.dawarich.test/\"}'::jsonb"
        ] do
      Repo.query!("UPDATE users SET #{sql} WHERE id=73901")
      before = snapshot(73901)
      assert match?({:handoff, _}, ApiKeys.rotate(73901, c.salt, c.context)), sql
      assert same?(snapshot(73901), before)

      Repo.query!(
        "UPDATE users SET email='a11rest-key-73901@dawarich.test',provider=NULL,otp_required_for_login=false,status=1,locked_at=NULL,deleted_at=NULL,settings='{\"timezone\":\"Europe/Berlin\",\"onboarding_completed\":true}'::jsonb WHERE id=73901"
      )
    end

    before = snapshot(73901)
    assert match?({:handoff, _}, ApiKeys.rotate(73901, "stale", c.context))
    assert match?({:handoff, _}, ApiKeys.rotate(73901, c.salt, %{c.context | self_hosted: false}))
    assert match?({:handoff, _}, ApiKeys.rotate(73901, c.salt, %{c.context | oidc: true}))
    assert same?(snapshot(73901), before)
    Repo.query!("UPDATE users SET email='legacy-invalid-email' WHERE id=73901")
    assert {:ok, _} = ApiKeys.rotate(73901, c.salt, c.context)
    assert Accounts.get(73901).email == "legacy-invalid-email"
  end

  test "key creation rotation and lookup never log usable credentials", c do
    previous = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous) end)
    old_key = snapshot(73901)["api_key"]

    log =
      capture_log([level: :debug], fn ->
        for form <- [:query, :bearer], do: assert(lookup(old_key, form) == {200, 73901})
        assert {:ok, actor} = ApiKeys.rotate(73901, c.salt, c.context)
        send(self(), {:rotated, actor})
        for form <- [:query, :bearer], do: assert(lookup(actor.api_key, form) == {200, 73901})
      end)

    assert_received {:rotated, actor}
    assert log =~ "SELECT"

    for secret <- [old_key, actor.api_key, actor.encrypted_password, "a11rest-key-password-42"] do
      absent = not String.contains?(log, secret)
      assert absent
    end
  end

  defp lookup(key, form) do
    conn =
      if form == :query do
        conn =
          Plug.Test.conn("GET", "/api/v1/points?" <> URI.encode_query(%{"api_key" => key}))
          |> fetch_query_params()

        assign(conn, :api_params, conn.query_params)
      else
        Plug.Test.conn("GET", "/api/v1/points")
        |> assign(:api_params, %{})
        |> put_req_header("authorization", "Bearer " <> key)
      end

    conn = conn |> put_req_header("accept", "application/json") |> DawarichWeb.Api.Auth.call([])
    if conn.assigns[:api_user], do: {200, conn.assigns.api_user.id}, else: {conn.status, nil}
  end

  defp snapshot(id),
    do:
      Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows
      |> hd()
      |> hd()

  defp same?(left, right), do: left == right

  defp changed(before, after_row),
    do: Enum.filter(Map.keys(before), &(before[&1] != after_row[&1])) |> Enum.sort()

  defp effects,
    do:
      {Repo.query!("SELECT count(*) FROM job_outbox").rows,
       Repo.query!("SELECT count(*) FROM oban.oban_jobs").rows,
       Repo.query!("SELECT count(*) FROM family_memberships").rows}
end
