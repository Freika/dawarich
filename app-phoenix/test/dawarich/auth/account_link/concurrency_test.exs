defmodule Dawarich.Auth.AccountLink.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Ecto.Query
  import Plug.Conn
  alias Dawarich.Auth.AccountLink.{Confirmation, SignIn}
  alias Dawarich.{Repo, ScratchRepo, Auth.Account, RailsCookies, Test.RailsUser}
  alias DawarichWeb.{AuthAccountLink.Http, RailsCsrf}
  @source "test/fixtures/auth/account_link/requests.json" |> File.read!() |> Jason.decode!()
  @now ~U[2026-10-05 12:00:00.000000Z]
  @owned for n <- 1..4, do: {911_455_000 + n, "a11e-concurrent-#{n}@example.invalid"}
  @secret "a11e-concurrency-synthetic-cookie-secret"

  defmodule FailedRepo do
    defdelegate one(query, opts), to: Repo
    defdelegate query!(sql, params, opts), to: Repo

    def update!(changeset, opts) do
      if Map.has_key?(changeset.changes, :sign_in_count), do: raise("a11e-later-callback")
      Repo.update!(changeset, opts)
    end
  end

  defp context, do: %{self_hosted: true, oidc: true, clock: fn -> @now end, ip: "198.51.100.234"}

  defp session(id, uid) do
    @source["challenge_en"]["session"]
    |> put_in(["pending_oauth_link", "user_id"], id)
    |> put_in(["pending_oauth_link", "uid"], uid)
  end

  defp actor(id, email), do: from(u in Account, where: u.id == ^id or u.email == ^email)

  defp worker(id, uid) do
    parent = self()

    task =
      Task.async(fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
          [[pid]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
          refute Repo.in_transaction?()
          assert Repo.get!(Account, id).provider == nil

          assert {:ok, prepared} =
                   Confirmation.prepare(session(id, uid), "safepassword12", context())

          send(parent, {:prepared, self(), pid, prepared.user.sign_in_count})

          receive do
            :commit ->
              outcome =
                try do
                  {:ok, linked} = Confirmation.commit(prepared, context())
                  {:ok, signed} = SignIn.commit(linked, context())
                  {:ok, signed.user.sign_in_count}
                rescue
                  error in Ecto.ConstraintError -> {:error, error.__struct__}
                end

              send(parent, {:committed, self(), outcome})
          end

          receive do: (:stop -> :ok)
        end)
      end)

    Process.put(:a11e_workers, [task | Process.get(:a11e_workers, [])])
    task
  end

  defp prepared(task) do
    assert_receive {:prepared, pid, backend, 0}, 5_000
    assert pid == task.pid
    backend
  end

  defp commit(task) do
    send(task.pid, :commit)
    assert_receive {:committed, pid, outcome}, 5_000
    assert pid == task.pid
    outcome
  end

  test "prepared confirmations match source overlap and partial identity persistence" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      for {id, email} <- @owned, do: refute(Repo.exists?(actor(id, email)))

      try do
        for {id, email} <- @owned do
          RailsUser.insert!(%{
            id: id,
            email: email,
            provider: nil,
            uid: nil,
            settings: %{},
            encrypted_password: @source["challenge_en"]["before"]["encrypted_password"],
            sign_in_count: 0,
            failed_attempts: 2,
            failed_otp_attempts: 3
          })
        end

        [[observer]] = Repo.query!("SELECT pg_backend_pid()", [], log: false).rows
        refute Repo.in_transaction?()
        first = worker(911_455_001, "a11e-overlap")
        first_backend = prepared(first)
        second = worker(911_455_001, "a11e-overlap")
        second_backend = prepared(second)
        assert MapSet.size(MapSet.new([observer, first_backend, second_backend])) == 3
        assert commit(first) == {:ok, 1}
        assert commit(second) == {:ok, 1}
        durable = Repo.get!(Account, 911_455_001)
        assert durable.provider == "openid_connect" and durable.uid == "a11e-overlap"

        assert durable.sign_in_count ==
                 @source["overlap"]["responses"]
                 |> List.last()
                 |> get_in(["after", "sign_in_count"])

        assert durable.failed_attempts == 0 and durable.failed_otp_attempts == 3
        for task <- [first, second], do: send(task.pid, :stop)
        for task <- [first, second], do: Task.await(task)
        Process.put(:a11e_workers, [])
        first = worker(911_455_002, "a11e-unique")
        one = prepared(first)
        second = worker(911_455_003, "a11e-unique")
        two = prepared(second)
        assert MapSet.size(MapSet.new([observer, one, two])) == 3
        assert commit(first) == {:ok, 1}
        assert commit(second) == {:error, Ecto.ConstraintError}
        assert Repo.get!(Account, 911_455_003).provider == nil
        assert Repo.get!(Account, 911_455_003).sign_in_count == 0
        for task <- [first, second], do: send(task.pid, :stop)
        for task <- [first, second], do: Task.await(task)
        Process.put(:a11e_workers, [])
        old = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})
        System.put_env("SELF_HOSTED", "true")
        System.put_env("APPLICATION_PROTOCOL", "http")
        System.put_env("RAILS_ENV", "test")
        previous_secret = Application.get_env(:dawarich, :rails_secret)
        Application.put_env(:dawarich, :rails_secret, @secret)
        pending = session(911_455_004, "a11e-durable")

        {pending, _} =
          Dawarich.Auth.SessionCookie.for_form(
            Map.drop(pending, ~w(session_id _csrf_token)),
            @secret
          )

        raw =
          URI.encode_query(%{
            "password" => "safepassword12",
            "authenticity_token" =>
              RailsCsrf.masked_form_token(pending, "/auth/account_link/challenge", "POST")
          })

        conn =
          Plug.Test.conn("POST", "http://www.example.com/auth/account_link/challenge", raw)
          |> put_req_header("content-type", "application/x-www-form-urlencoded")
          |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
          |> Plug.Test.put_req_cookie(
            "_dawarich_session",
            RailsCookies.encrypt(pending, "_dawarich_session", @secret)
          )
          |> Map.put(:remote_ip, {198, 51, 100, 234})

        at = DateTime.to_unix(@now)

        keys =
          for {name, value} <- [
                {"auth/account_link_challenge_session", 911_455_004},
                {"auth/account_link_challenge_ip", "198.51.100.234"}
              ],
              do: DawarichWeb.RateLimit.Rules.key(at, 900, name, value)

        for key <- keys, do: assert(Dawarich.State.count(ScratchRepo, key) == 0)

        try do
          assert_raise RuntimeError, "a11e-later-callback", fn ->
            Http.call(conn,
              enabled: true,
              context:
                Map.merge(context(), %{
                  repo: FailedRepo,
                  secret: @secret,
                  rate_repo: ScratchRepo,
                  rate_now: at
                }),
              fallback: fn _ -> flunk("post-effect Rails replay") end
            )
          end

          durable = Repo.get!(Account, 911_455_004)
          assert durable.provider == @source["later_callback_failure"]["durable"]["provider"]
          assert durable.uid == "a11e-durable"
          assert durable.failed_attempts == 0 and durable.sign_in_count == 0
          refute Repo.in_transaction?()
        after
          for {key, value} <- old,
              do: if(value, do: System.put_env(key, value), else: System.delete_env(key))

          Application.put_env(:dawarich, :rails_secret, previous_secret)

          for key <- keys,
              do:
                ScratchRepo.query!("DELETE FROM phoenix.counters WHERE key=$1", [key], log: false)
        end
      after
        for task <- Process.get(:a11e_workers, []), do: Task.shutdown(task, :brutal_kill)
        Process.delete(:a11e_workers)

        for {id, email} <- @owned,
            do: Repo.delete_all(from(u in Account, where: u.id == ^id and u.email == ^email))
      end
    end)
  end
end
