defmodule Dawarich.Seeds.BootstrapUserTest do
  use Dawarich.JobsCase

  import ExUnit.CaptureLog

  alias Dawarich.A12hSeeds, as: Corpus
  alias Dawarich.Seeds.BootstrapUser

  @salt "$2a$12$PhoenixA12eCorpusSaltu"
  @env %{"SELF_HOSTED" => "true", "TIME_ZONE" => "Europe/Berlin"}

  defmodule CallbackFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo
    defdelegate rollback(reason), to: Dawarich.ScratchRepo

    def query!(sql, params, opts) do
      if String.starts_with?(sql, "UPDATE users SET status=1"),
        do: raise("synthetic seed activation failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  setup do
    [[previous]] =
      rows(
        "SELECT pg_get_expr(adbin,adrelid) FROM pg_attrdef JOIN pg_attribute ON attrelid=adrelid AND attnum=adnum WHERE adrelid='users'::regclass AND attname='visits_redetected_at'"
      )

    rows(
      "ALTER TABLE users ALTER visits_redetected_at SET DEFAULT timestamp '2026-10-01 12:00:00'"
    )

    on_exit(fn ->
      rows("ALTER TABLE users ALTER visits_redetected_at SET DEFAULT #{previous}")
    end)

    :ok
  end

  test "initial administrator matches Rails self-hosted callback state and skips a scoped user" do
    for name <- ["A12h_fresh", "A12h_soft_deleted_only", "A12h_partial_tables", "A12h_rerun"] do
      c = Corpus.case!(name)
      Corpus.load!(ScratchRepo, c["seed"], ["users"])
      rows("SELECT setval(pg_get_serial_sequence('users','id'),1,false)")
      assert BootstrapUser.run(ScratchRepo, options(c)) == :ok

      equal = Corpus.snapshot(ScratchRepo, "users") == c["after"]["users"]

      differences =
        for {actual, expected} <-
              Enum.zip(Corpus.snapshot(ScratchRepo, "users"), c["after"]["users"]),
            {key, value} <- expected,
            actual[key] != value,
            do: key

      assert equal, "#{name}: bootstrap differs in columns #{inspect(Enum.uniq(differences))}"
      before = Corpus.snapshot(ScratchRepo, "users")
      assert BootstrapUser.run(ScratchRepo, options(c)) == :ok
      assert Corpus.snapshot(ScratchRepo, "users") == before
    end

    c = Corpus.case!("A12h_fresh")
    Corpus.load!(ScratchRepo, %{}, ["users"])

    error =
      assert_raise RuntimeError, fn -> BootstrapUser.run(CallbackFailureRepo, options(c)) end

    assert error.message == "synthetic seed activation failure"

    assert [[true, 1, 1, expiry, key_size]] =
             rows("SELECT admin,status,plan,active_until,length(api_key) FROM users")

    assert expiry == ~N[2126-10-01 12:00:00.000000]
    assert key_size == 64
    assert BootstrapUser.run(ScratchRepo, options(c)) == :ok
    assert rows("SELECT active_until FROM users") == [[expiry]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  test "seed credentials are usable but absent from logs" do
    previous_level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: previous_level) end)
    c = Corpus.case!("A12h_fresh")
    Corpus.load!(ScratchRepo, %{}, ["users"])

    log =
      capture_log([level: :debug], fn ->
        assert BootstrapUser.run(ScratchRepo, options(c)) == :ok
      end)

    [[email, hash, key]] = rows("SELECT email,encrypted_password,api_key FROM users")
    assert email == "demo@dawarich.app"
    valid = Bcrypt.verify_pass("safepassword", hash)
    assert valid
    wrong = Bcrypt.verify_pass("wrong-password", hash)
    refute wrong
    format = Regex.match?(~r/\A\$2a\$12\$/, hash)
    assert format
    key_valid = Regex.match?(~r/\A[0-9a-f]{64}\z/, key)
    assert key_valid
    assert rows("SELECT count(*) FROM users WHERE api_key=$1", [key]) == [[1]]
    leaked = Enum.any?([email, "safepassword", hash, key], &String.contains?(log, &1))
    refute leaked, "bootstrap credentials must be absent from logs"
    Corpus.load!(ScratchRepo, %{}, ["users"])

    log =
      capture_log([level: :debug], fn ->
        assert BootstrapUser.run(ScratchRepo, env: @env, now: Corpus.now()) == :ok
      end)

    [[random_hash, random_key]] = rows("SELECT encrypted_password,api_key FROM users")
    assert random_hash != hash
    assert random_key != key
    valid = Bcrypt.verify_pass("safepassword", random_hash)
    assert valid

    leaked =
      Enum.any?([email, "safepassword", random_hash, random_key], &String.contains?(log, &1))

    refute leaked, "random bootstrap credentials must be absent from logs"
  end

  defp options(c) do
    row =
      Enum.find(c["after"]["users"], &(&1["email"] == "demo@dawarich.app")) ||
        Corpus.case!("A12h_fresh")["after"]["users"] |> hd()

    bytes = Base.decode16!(row["api_key"], case: :lower)
    [env: @env, now: Corpus.now(), salt: @salt, random_bytes: fn 32 -> bytes end]
  end
end
