defmodule DawarichWeb.Api.TwoFactorEndpointTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  @moduletag api_public_only: true
  @moduletag :capture_log
  @moduletag api_now: ~U[2026-10-04 12:00:00.000000Z]
  @key "a4otp-endpoint-synthetic"
  @crypto "../../fixtures/active_record_encryption.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
  @env Enum.find(@crypto["environments"], &(&1["name"] == "explicit keys"))["env"]
  @actions [
    {"POST", "/api/v1/users/me/two_factor/setup"},
    {"POST", "/api/v1/users/me/two_factor/confirm"},
    {"POST", "/api/v1/users/me/two_factor/backup_codes"},
    {"DELETE", "/api/v1/users/me/two_factor"}
  ]

  setup do
    names =
      Enum.filter(Map.keys(@env), &String.starts_with?(&1, "OTP_")) ++
        ~w(SELF_HOSTED DAWARICH_RAILS_SLICES DAWARICH_PHOENIX_AUTH)

    previous = Map.new(names, &{&1, System.get_env(&1)})

    Enum.each(@env, fn {name, value} ->
      if String.starts_with?(name, "OTP_"), do: System.put_env(name, value)
    end)

    System.put_env("SELF_HOSTED", "true")
    System.delete_env("DAWARICH_RAILS_SLICES")
    System.delete_env("DAWARICH_PHOENIX_AUTH")

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end)

    owner =
      user!(%{
        status: 0,
        api_key: @key,
        settings: %{"timezone" => "UTC"},
        encrypted_password: Bcrypt.hash_pwd_salt("safepassword12", log_rounds: 4)
      })

    other = user!(%{settings: %{}})
    %{owner: owner, other: other}
  end

  test "API OTP failures retain inherited auth payment and availability precedence", c do
    assert native_route?()
    before = state(c)
    System.delete_env("OTP_ENCRYPTION_PRIMARY_KEY")

    for {method, target} <- @actions do
      assert {401, headers, ""} = call(c, method, target, "{}", key: "unknown-synthetic")
      assert values(headers, "vary") == []
      assert values(headers, "cache-control") == ["no-cache"]
      assert values(headers, "x-dawarich-response") == ["Hey, I'm alive!"]
      Repo.query!("UPDATE users SET status=3 WHERE id=$1", [c.owner], log: false)
      assert {402, _, body} = call(c, method, target, "{}")
      assert Jason.decode!(body)["error"] == "payment_required"
      Repo.query!("UPDATE users SET status=0 WHERE id=$1", [c.owner], log: false)
      assert {503, headers, body} = call(c, method, target, ~s({"password":"wrong"}))
      assert body == ~s({"error":"two_factor_not_available"})
      assert values(headers, "x-dawarich-response") == ["Hey, I'm alive and authenticated!"]
      assert values(headers, "set-cookie") == []
      assert values(headers, "content-type") == ["application/json; charset=utf-8"]
      assert values(headers, "vary") == ["Accept"]
    end

    assert state(c) == before
    System.put_env("OTP_ENCRYPTION_PRIMARY_KEY", @env["OTP_ENCRYPTION_PRIMARY_KEY"])

    for {method, target} <- @actions do
      assert {401, _, body} = call(c, method, target, "{}")
      assert Jason.decode!(body)["error"] == "password_required"
    end

    no_upstream!(c.upstream)
  end

  test "API unsupported requests replay original bytes before SQL or crypto effects", c do
    assert native_route?()
    before = state(c)

    for {target, body, opts} <- [
          {"/api/v1/users/me/two_factor/setup", ~s({"password":{"nested":"safepassword12"}}), []},
          {"/api/v1/users/me/two_factor/setup", ~s({"password":["safepassword12"]}), []},
          {"/api/v1/users/me/two_factor/confirm",
           ~s({"password":"safepassword12","otp_code":["123456"]}), []},
          {"/api/v1/users/me/two_factor/setup?password=x&password=y", "{}", []},
          {"/api/v1/users/me/two_factor/setup", ~s({"password":"x","password":"y"}), []},
          {"/api/v1/users/me/two_factor/setup", "password=x&password=y",
           [type: "application/x-www-form-urlencoded"]},
          {"/api/v1/users/me/two_factor/setup?format=xml", ~s({"password":"safepassword12"}), []},
          {"/api/v1/users/me/two_factor/setup", ~s({"password":"safepassword12"}),
           [headers: [{"X-Dawarich-Client", "ios"}]]},
          {"/api/v1/users/me/two_factor/setup", "{}",
           [headers: [{"Cookie", "remember_user_token=synthetic-unsupported"}]]},
          {"/api/v1/users/me/two_factor/setup", "{}",
           [headers: [{"X-HTTP-Method-Override", "DELETE"}]]},
          {"/api/v1/users/me/two_factor/setup", "_method=DELETE&password=safepassword12",
           [type: "application/x-www-form-urlencoded"]}
        ] do
      replay!(c, "POST", target, body, opts)
      assert state(c) == before
    end
  end

  test "API post-save failure is terminal and never reaches Puma", c do
    assert native_route?()
    secret = Totp.generate_secret(:binary.copy(<<4>>, 20))
    {:ok, ciphertext} = Secret.encrypt(secret, @env)
    user = Repo.get!(Account, c.owner)

    Repo.update!(
      Ecto.Changeset.change(user, otp_secret: ciphertext, otp_required_for_login: true),
      log: false
    )

    Repo.query!(
      """
      CREATE FUNCTION pg_temp.a4otp_clear_failure() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.id = #{c.owner} AND OLD.otp_secret IS NOT NULL AND NEW.otp_secret IS NULL THEN
          RAISE EXCEPTION 'synthetic API clear-save failure';
        END IF;
        RETURN NEW;
      END $$
      """,
      [],
      log: false
    )

    Repo.query!(
      "CREATE TRIGGER a4otp_clear_failure BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION pg_temp.a4otp_clear_failure()",
      [],
      log: false
    )

    code = Totp.at(secret, DateTime.to_unix(c.api_now))
    before = state(c)

    assert {500, _, _} =
             call(
               c,
               "DELETE",
               "/api/v1/users/me/two_factor",
               Jason.encode!(%{"password" => "safepassword12", "otp_code" => code})
             )

    user = Repo.get!(Account, c.owner)
    assert user.consumed_timestep == div(DateTime.to_unix(c.api_now), 30)
    assert user.otp_secret == ciphertext and user.otp_required_for_login
    assert state(c).effects == before.effects
    assert state(c).other == before.other
    no_upstream!(c.upstream)
  end

  defp native_route? do
    case Phoenix.Router.route_info(
           DawarichWeb.Router,
           "POST",
           "/api/v1/users/me/two_factor/setup",
           "localhost"
         ) do
      %{plug: DawarichWeb.Api.TwoFactorController} -> true
      _ -> false
    end
  end

  defp state(c) do
    %{
      owner:
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [c.owner], log: false).rows,
      other:
        Repo.query!("SELECT to_jsonb(u) FROM users u WHERE id=$1", [c.other], log: false).rows,
      effects: rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id"),
      jobs: Repo.query!("SELECT count(*) FROM job_outbox", [], log: false).rows,
      scratch: rows("SELECT count(*) FROM users")
    }
  end

  defp call(c, method, target, body, opts \\ []),
    do: c |> submit(method, target, body, opts) |> read_response()

  defp submit(c, method, target, body, opts) do
    client =
      request(
        c.port,
        target,
        [
          {"Accept", "application/json"},
          {"Content-Type", Keyword.get(opts, :type, "application/json")},
          {"Content-Length", Integer.to_string(byte_size(body))},
          {"Authorization", "Bearer " <> Keyword.get(opts, :key, @key)},
          {"X-Original", "synthetic-byte-check"}
        ] ++
          Keyword.get(opts, :headers, []),
        method
      )

    send_raw(client, body)
    client
  end

  defp replay!(c, method, target, body, opts) do
    client = submit(c, method, target, body, opts)
    puma = accept(c.upstream)
    {head, rest} = read_head(puma)
    assert request_line(head) == "#{method} #{target} HTTP/1.1"
    assert header(head, "x-original") == ["synthetic-byte-check"]
    assert header(head, "content-type") == [Keyword.get(opts, :type, "application/json")]
    assert read_at_least(puma, rest, byte_size(body)) == body
    reply(puma, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    assert {200, _, "rails"} = read_response(client)
  end
end
