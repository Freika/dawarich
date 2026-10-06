defmodule Dawarich.A12f3bM07Test do
  use Dawarich.JobsCase
  alias Dawarich.Auth.Otp.Lockout
  alias Dawarich.Mail.OtpAccountLockedWorker
  alias Dawarich.{RailsCache.Wire, Redis}
  @now ~U[2026-10-04 12:00:00.000000Z]

  setup do
    start_oban(:mail_lockout)
    for spec <- Redis.cache_child_specs(), do: start_supervised!(spec)
    previous = Map.take(System.get_env(), ~w(DOMAIN RAILS_ENV))
    System.put_env(%{"DOMAIN" => "mail.example.test", "RAILS_ENV" => "production"})

    on_exit(fn ->
      Enum.each(~w(DOMAIN RAILS_ENV), &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok
  end

  defp user! do
    [[id]] =
      rows(
        "INSERT INTO users(email,settings,created_at,updated_at) VALUES('otp@example.test','{\"locale\":\"de\"}',now(),now()) RETURNING id"
      )

    key = "otp_lockout_email_throttle/user/#{id}"
    Redis.cache_command(["DEL", key])

    on_exit(fn ->
      {:ok, connection} =
        Redix.start_link(Application.fetch_env!(:dawarich, :redis)[:url], database: 0)

      Redix.command(connection, ["DEL", key])
      GenServer.stop(connection)
    end)

    {id, key}
  end

  @tag a12f3b_case: "M07a"
  test "OTP lockout mail preserves rate accounting and lock timestamps" do
    {id, key} = user!()
    opts = [now: @now, oban: :mail_lockout, locale: "fr"]
    for _ <- 1..9, do: assert(Lockout.register_failed_attempt(ScratchRepo, id, opts) == :ok)

    assert rows("SELECT failed_otp_attempts,otp_locked_at FROM users WHERE id=$1", [id]) == [
             [9, nil]
           ]

    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert Lockout.register_failed_attempt(ScratchRepo, id, opts) == :ok
    assert {:ok, bytes} = Redis.cache_command(["GET", key])
    assert {:ok, %{value: true, expires_at: expires}} = Wire.decode(bytes)
    assert expires == DateTime.to_unix(@now) + 3600

    for _ <- 1..3,
        do:
          assert(
            Lockout.register_failed_attempt(
              ScratchRepo,
              id,
              Keyword.put(opts, :now, DateTime.add(@now, 10))
            ) == :ok
          )

    assert Redis.cache_command(["GET", key]) == {:ok, bytes}
    assert rows("SELECT failed_otp_attempts FROM users WHERE id=$1", [id]) == [[10]]
    [[args]] = rows("SELECT args FROM oban.oban_jobs")
    assert OtpAccountLockedWorker.perform(%Oban.Job{args: args}) == :ok
    assert_received {:mail, mail}

    assert {:ok, mail.subject} ==
             Dawarich.I18n.t("de", "mailers.users.otp_account_locked.subject")

    assert mail.text =~ "/users/password/new"
    assert mail.html =~ "/users/password/new"
  end

  @tag a12f3b_case: "M07b"
  test "OTP mail enqueue failure preserves source lock and accounting order" do
    {id, key} = user!()
    rows("UPDATE users SET failed_otp_attempts=9 WHERE id=$1", [id])

    assert_raise RuntimeError, "synthetic enqueue rejection", fn ->
      Lockout.register_failed_attempt(ScratchRepo, id,
        now: @now,
        enqueue: fn _ -> raise "synthetic enqueue rejection" end
      )
    end

    assert rows("SELECT failed_otp_attempts,otp_locked_at IS NOT NULL FROM users WHERE id=$1", [
             id
           ]) == [[10, true]]

    assert {:ok, bytes} = Redis.cache_command(["GET", key])
    assert is_binary(bytes)
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    args = %{"user_id" => id, "locale" => "fr", "event_id" => Ecto.UUID.generate()}
    Process.put(:transport_result, {:error, :rejected})
    assert OtpAccountLockedWorker.perform(%Oban.Job{args: args}) == {:error, :rejected}
    assert_received {:mail, _}
    assert Redis.cache_command(["GET", key]) == {:ok, bytes}
    assert Lockout.register_failed_attempt(ScratchRepo, id, now: @now, oban: :mail_lockout) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
  end
end
