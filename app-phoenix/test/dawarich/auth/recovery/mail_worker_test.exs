defmodule Dawarich.Auth.Recovery.MailWorkerTest do
  use Dawarich.JobsCase
  use Oban.Testing, repo: Dawarich.ScratchRepo

  alias Dawarich.{RailsCookies, RailsSecret}
  alias Dawarich.Auth.Recovery.{Mail, MailWorker, Notification, Token}
  alias Dawarich.Test.MailWire

  @raw String.duplicate("q", 20)
  @sender "Dawarich <a11a@dawarich.test>"
  @env ~w(SMTP_FROM SMTP_SERVER E2E_SMTP_PORT DOMAIN)

  setup do
    saved = for name <- @env, value = System.get_env(name), do: {name, value}
    Enum.each(@env, &System.delete_env/1)
    System.put_env("SMTP_FROM", @sender)
    System.put_env("DOMAIN", "dawarich.example.test")

    on_exit(fn ->
      Enum.each(@env, &System.delete_env/1)
      Enum.each(saved, fn {name, value} -> System.put_env(name, value) end)
    end)

    start_oban(RecoveryMailOban)
    :ok
  end

  defp user!(attrs \\ %{}) do
    secret = RailsSecret.fetch()

    [[id]] =
      rows(
        "INSERT INTO users (email, settings, reset_password_token, unlock_token, deleted_at, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id",
        [
          "recovery-#{System.unique_integer([:positive])}@dawarich.test",
          %{"locale" => "de"},
          Map.get(attrs, :reset, Token.digest(:reset_password_token, @raw, secret)),
          Map.get(attrs, :unlock),
          Map.get(attrs, :deleted_at)
        ]
      )

    id
  end

  defp enqueued!(id, kind \\ :reset_password_instructions, now \\ DateTime.utc_now()) do
    column =
      if kind == :reset_password_instructions, do: :reset_password_token, else: :unlock_token

    digest = Token.digest(column, @raw, RailsSecret.fetch())
    notification = %Notification{kind: kind, user_id: id, raw: @raw, digest: digest, locale: "fr"}
    assert MailWorker.enqueue(notification, RecoveryMailOban, now) == :ok
    [[args]] = rows("SELECT args FROM oban.oban_jobs ORDER BY id DESC LIMIT 1")
    args
  end

  test "enqueue writes one mailers job whose link is sealed" do
    args = enqueued!(user!())

    assert rows("SELECT worker, queue, max_attempts FROM oban.oban_jobs") == [
             [inspect(MailWorker), "mailers", 20]
           ]

    assert args |> Map.keys() |> Enum.sort() == ~w(digest event_id kind locale sealed user_id)
    refute Jason.encode!(args) =~ @raw

    assert RailsCookies.decrypt(
             args["sealed"],
             "dawarich.auth.recovery",
             RailsSecret.fetch(),
             DateTime.utc_now()
           ) == {:ok, @raw}
  end

  test "perform mails the current link once, in the request's locale" do
    id = user!()
    args = enqueued!(id)

    assert perform_job(MailWorker, args) == :ok
    assert_received {:mail, mail}
    assert mail.format == :html_only
    assert mail.from == @sender and mail.reply_to == @sender

    assert mail.html =~
             ~s(href="https://dawarich.example.test/users/password/edit?reset_password_token=#{@raw}")

    assert {:ok, mail.subject} ==
             Dawarich.I18n.t("fr", "devise.mailer.reset_password_instructions.subject")

    assert mail.message_id =~ "@dawarich.example.test>"

    assert perform_job(MailWorker, args) == :ok
    refute_received {:mail, _}

    assert rows("SELECT provider_key FROM phoenix.delivery_claims") == [
             ["#{id}:#{args["digest"]}"]
           ]
  end

  test "a superseded or consumed digest and a deleted account send nothing" do
    for attrs <- [%{reset: "superseded"}, %{reset: nil}, %{deleted_at: NaiveDateTime.utc_now()}] do
      assert perform_job(MailWorker, enqueued!(user!(attrs))) == :ok
    end

    refute_received {:mail, _}
  end

  test "a seal older than Devise's reset window is cancelled" do
    within = MailWire.fixture()["reset_password_within_seconds"]
    id = user!()

    late =
      enqueued!(id, :reset_password_instructions, DateTime.add(DateTime.utc_now(), -within - 1))

    assert {:cancel, _} = perform_job(MailWorker, late)

    fresh =
      enqueued!(id, :reset_password_instructions, DateTime.add(DateTime.utc_now(), -within + 60))

    assert perform_job(MailWorker, fresh) == :ok
    assert_received {:mail, _}
  end

  test "an SMTP failure is retried under the same claim" do
    args = enqueued!(user!())
    Process.put(:transport_result, {:error, {:permanent_failure, "554"}})
    assert perform_job(MailWorker, args) == {:error, {:permanent_failure, "554"}}
    Process.delete(:transport_result)
    assert perform_job(MailWorker, args) == :ok
    assert rows("SELECT delivered_at IS NOT NULL FROM phoenix.delivery_claims") == [[true]]
  end

  test "unlock instructions carry the unlock link" do
    unlock = Token.digest(:unlock_token, @raw, RailsSecret.fetch())

    assert perform_job(MailWorker, enqueued!(user!(%{unlock: unlock}), :unlock_instructions)) ==
             :ok

    assert_received {:mail, mail}
    assert mail.html =~ "/users/unlock?unlock_token=#{@raw}"
  end

  @deliverable %{
    "RAILS_ENV" => "production",
    "SMTP_FROM" => @sender,
    "SMTP_SERVER" => "smtp.example.test",
    "DOMAIN" => "dawarich.example.test"
  }

  test "deliverable?/1 needs a sender, a server and DOMAIN" do
    base = @deliverable

    assert MailWorker.deliverable?(base)

    assert MailWorker.deliverable?(
             base
             |> Map.delete("SMTP_SERVER")
             |> Map.put("E2E_SMTP_PORT", "1025")
           )

    for name <- ~w(SMTP_FROM SMTP_SERVER DOMAIN),
        do: refute(MailWorker.deliverable?(Map.put(base, name, " ")))

    for domain <- ["dawarich.example.test/path", "user@dawarich.example.test"],
        do: refute(MailWorker.deliverable?(Map.put(base, "DOMAIN", domain)), domain)

    assert MailWorker.deliverable?(Map.put(base, "DOMAIN", "dawarich.example.test:3000"))
  end

  test "deliverable?/1 only where Rails' mailer is the one Phoenix mirrors: production and staging" do
    assert MailWorker.deliverable?(Map.put(@deliverable, "RAILS_ENV", "staging"))

    for env <- ["development", "test", "Production", "", " "],
        do: refute(MailWorker.deliverable?(Map.put(@deliverable, "RAILS_ENV", env)), env)

    refute MailWorker.deliverable?(Map.delete(@deliverable, "RAILS_ENV"))
  end

  test "deliverable?/1 only when Phoenix can configure the transport Rails would use" do
    for auth <- ~w(plain login cram_md5 none),
        do:
          assert(
            MailWorker.deliverable?(Map.put(@deliverable, "SMTP_AUTHENTICATION", auth)),
            auth
          )

    for auth <- ~w(xoauth2 ntlm gssapi digest_md5),
        do:
          refute(
            MailWorker.deliverable?(Map.put(@deliverable, "SMTP_AUTHENTICATION", auth)),
            auth
          )

    refute MailWorker.deliverable?(
             Map.put(@deliverable, "SMTP_OPENSSL_VERIFY_MODE", "client_once")
           )

    refute MailWorker.deliverable?(
             @deliverable
             |> Map.delete("SMTP_SERVER")
             |> Map.put("E2E_SMTP_PORT", "abc")
           )
  end

  test "the two Devise mails equal Rails' rendering and framing" do
    fixture = MailWire.fixture()

    for entry <- fixture["mails"] do
      {:ok, message} =
        Mail.build(
          String.to_existing_atom(entry["kind"]),
          entry["to"],
          entry["locale"],
          entry["seed"],
          fixture["base_url"],
          %{"SMTP_FROM" => entry["from"]}
        )

      assert MailWire.phoenix(message) == MailWire.rails(entry),
             entry["kind"] <> " " <> entry["locale"]
    end
  end
end
