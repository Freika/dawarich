defmodule DawarichWeb.AuthRecoveryActivationTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Auth.Recovery.{MailWorker, Token}
  alias DawarichWeb.{AuthRecovery, RailsCsrf}

  @email "reset-flow@dawarich.test"
  @env ~w(SELF_HOSTED SMTP_FROM DOMAIN APPLICATION_PROTOCOL RAILS_ENV RACK_ENV)

  setup do
    saved = for name <- @env, value = System.get_env(name), do: {name, value}
    Enum.each(@env, &System.delete_env/1)
    System.put_env("SELF_HOSTED", "true")
    System.put_env("SMTP_FROM", "Dawarich <a11a@dawarich.test>")
    System.put_env("DOMAIN", "dawarich.example.test")

    on_exit(fn ->
      Enum.each(@env, &System.delete_env/1)
      Enum.each(saved, fn {name, value} -> System.put_env(name, value) end)
    end)

    [[id]] =
      rows(
        "INSERT INTO users (email, settings, created_at, updated_at) VALUES ($1, '{}', now(), now()) RETURNING id",
        [@email]
      )

    %{id: id}
  end

  defp session, do: %{"session_id" => "a11a-guest", "_csrf_token" => RailsCsrf.new_token()}

  defp form_conn(method, path, fields, session, enqueue) do
    body = URI.encode_query(fields)
    context = %{repo: ScratchRepo, registration_enabled: false, oidc: false, self_hosted: true}
    context = Map.put(context, :log_rounds, 4)
    context = if enqueue, do: Map.put(context, :enqueue, enqueue), else: context

    Plug.Test.conn(method, path, body)
    |> put_req_header(
      "cookie",
      "_dawarich_session=" <>
        RailsCookies.encrypt(session, "_dawarich_session", RailsSecret.fetch())
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> AuthRecovery.Http.call(
      enabled: true,
      context: context,
      fallback: &put_private(&1, :handed_to_rails, true)
    )
  end

  defp post(email, enqueue, token \\ nil) do
    session = session()

    form_conn(
      :post,
      "/users/password",
      [
        {"authenticity_token", token || RailsCsrf.masked_token(session)},
        {"user[email]", email}
      ],
      session,
      enqueue
    )
  end

  defp redeem(raw, password) do
    session = session()

    form_conn(
      :post,
      "/users/password",
      [
        {"_method", "put"},
        {"authenticity_token", RailsCsrf.masked_token(session)},
        {"user[reset_password_token]", raw},
        {"user[password]", password},
        {"user[password_confirmation]", password}
      ],
      session,
      nil
    )
  end

  defp digest(id), do: rows("SELECT reset_password_token FROM users WHERE id = $1", [id])

  test "the token, its sealed mail job and the paranoid notice commit together", ctx do
    start_oban(ActivationOban)
    conn = post(@email, &MailWorker.enqueue(&1, ActivationOban))

    assert conn.status == 303
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-recovery"]
    assert get_resp_header(conn, "location") == ["http://www.example.com/users/sign_in"]
    [[digest]] = digest(ctx.id)
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert args["digest"] == digest

    assert perform_job(MailWorker, args) == :ok
    assert_received {:mail, mail}
    [_, raw] = Regex.run(~r/reset_password_token=([A-Za-z0-9_-]+)/, mail.html)
    assert Token.digest(:reset_password_token, raw, RailsSecret.fetch()) == digest
  end

  test "the mailed link redeems through the adapter and the new password is the user's", ctx do
    start_oban(ActivationOban)
    post(@email, &MailWorker.enqueue(&1, ActivationOban))
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert perform_job(MailWorker, args) == :ok
    assert_received {:mail, mail}
    [_, raw] = Regex.run(~r/reset_password_token=([A-Za-z0-9_-]+)/, mail.html)

    conn = redeem(raw, "a-much-longer-new-password")

    assert conn.status == 303
    assert get_resp_header(conn, "location") == ["http://www.example.com/"]
    assert get_resp_header(conn, "x-dawarich-auth-owner") == ["native-recovery"]
    [[hash]] = rows("SELECT encrypted_password FROM users WHERE id = $1", [ctx.id])
    assert Bcrypt.verify_pass("a-much-longer-new-password", hash)
    assert digest(ctx.id) == [[nil]]
  end

  test "an unknown email answers the same notice and enqueues nothing" do
    start_oban(ActivationOban)
    conn = post("nobody@dawarich.test", &MailWorker.enqueue(&1, ActivationOban))
    assert conn.status == 303
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end

  test "a failed enqueue rolls the token back and answers 500", ctx do
    conn = post(@email, fn _ -> {:error, :boom} end)
    assert conn.status == 500
    assert digest(ctx.id) == [[nil]]
  end

  test "without a delivery owner the request goes to Rails before any effect", ctx do
    conn = post(@email, nil)
    assert conn.private[:handed_to_rails]
    assert conn.private.dawarich_raw_body =~ "user%5Bemail%5D="
    assert digest(ctx.id) == [[nil]]
  end

  test "a forged token hands the request and its body to Rails before any effect", ctx do
    conn = post(@email, fn _ -> flunk("enqueued") end, "forged")
    assert conn.private[:handed_to_rails]
    assert conn.private.dawarich_raw_body =~ "authenticity_token=forged"
    assert conn.status == nil
    assert digest(ctx.id) == [[nil]]
  end

  test "every response the adapter answers itself is halted" do
    start_oban(ActivationOban)
    enqueue = &MailWorker.enqueue(&1, ActivationOban)
    guest = session()

    answered = [
      post(@email, enqueue),
      post(@email, fn _ -> {:error, :boom} end),
      form_conn(:get, "/users/password/new", [], guest, enqueue),
      form_conn(:get, "/users/password/edit", [], guest, enqueue),
      redeem("synthetic", "short")
    ]

    System.put_env("APPLICATION_PROTOCOL", "https")
    System.put_env("RAILS_ENV", "production")
    answered = [form_conn(:get, "/users/password/new", [], guest, enqueue) | answered]

    assert Enum.map(answered, &{&1.state, &1.halted}) == List.duplicate({:sent, true}, 6)
    assert Enum.map(answered, & &1.status) == [301, 303, 500, 200, 302, 422]
  end
end
