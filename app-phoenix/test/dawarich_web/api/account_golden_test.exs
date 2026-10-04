defmodule DawarichWeb.Api.AccountGoldenTest.ClearValidationFailure do
  alias Dawarich.Repo
  defdelegate one(query, opts), to: Repo
  defdelegate query!(sql, params, opts), to: Repo
  defdelegate transaction(fun, opts), to: Repo

  def update!(changeset, opts) do
    changeset =
      if Map.has_key?(changeset.changes, :otp_secret) and is_nil(changeset.changes.otp_secret),
        do:
          changeset
          |> Ecto.Changeset.put_change(:email, nil)
          |> Ecto.Changeset.validate_required([:email]),
        else: changeset

    Repo.update!(changeset, opts)
  end
end

defmodule DawarichWeb.Api.AccountGoldenTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden
  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Secret, Totp}

  @path "test/fixtures/api_account/golden.json"
  @moduletag api_public_only: true
  @moduletag :capture_log
  @tables ~w(users families family_memberships instance_settings)
  @password "a4rest-account-synthetic-password"
  @backup "a4rest-account-synthetic-backup"
  @webhook "a4rest-account-synthetic-webhook"
  @moduletag api_now: ~U[2026-10-03 12:00:00.000000Z]

  test "crypto goldens validate response secrets and backup codes against actual storage", ctx do
    for name <- ["otp_setup_rotation", "otp_confirm"] do
      {kase, before} = prepare(name, ctx)
      ApiGolden.check(request(kase), ctx.port, ctx.upstream, crypto_options(kase, before))

      {kase, before} = prepare(name, ctx)

      invalid = [
        crypto: fn raw ->
          if kase["runtime_crypto"] == "setup" do
            Repo.query!("UPDATE users SET otp_secret=$1 WHERE id=954001", [ctx.encrypted_otp],
              log: false
            )
          else
            Repo.query!(
              "UPDATE users SET otp_backup_codes=$1 WHERE id=954001",
              [[ctx.backup_digest]],
              log: false
            )
          end

          validate_crypto!(kase, raw, before)
          crypto_body(kase, raw)
        end
      ]

      assert_raise ExUnit.AssertionError, fn ->
        ApiGolden.check(request(kase), ctx.port, ctx.upstream, invalid)
      end
    end
  end

  test "crypto goldens validate ETag and Content-Length against original response bytes", ctx do
    for name <- ["otp_setup", "otp_backup"] do
      {kase, before} = prepare(name, ctx)
      ApiGolden.check(request(kase), ctx.port, ctx.upstream, crypto_options(kase, before))
    end
  end

  test "crypto after-state distinguishes preserved values from regenerated values", ctx do
    for name <- ["otp_setup_rotation", "otp_backup_disabled_preserves_state"] do
      {kase, before} = prepare(name, ctx)
      ApiGolden.check(request(kase), ctx.port, ctx.upstream, crypto_options(kase, before))
      assert after_rows(Repo) == expected_after(kase, before, ctx)
    end
  end

  setup_all do
    {:ok, key} = ActiveRecordEncryption.key(%{"RAILS_ENV" => "test"})
    encrypted = ActiveRecordEncryption.encrypt("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", key)

    %{
      fixture: @path |> File.read!() |> Jason.decode!(),
      password_digest: Bcrypt.hash_pwd_salt(@password, log_rounds: 4),
      backup_digest: Bcrypt.hash_pwd_salt(@backup, log_rounds: 4),
      encrypted_otp: encrypted
    }
  end

  setup do
    {:ok, credentials} = ActiveRecordEncryption.credentials(%{"RAILS_ENV" => "test"})

    env = %{
      "OTP_ENCRYPTION_PRIMARY_KEY" => credentials.primary_key,
      "OTP_ENCRYPTION_DETERMINISTIC_KEY" => credentials.deterministic_key,
      "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => credentials.key_derivation_salt,
      "SELF_HOSTED" => "true",
      "DAWARICH_RAILS_SLICES" => nil
    }

    previous = Map.new(env, fn {name, _} -> {name, System.get_env(name)} end)

    Enum.each(env, fn {name, value} ->
      if value, do: System.put_env(name, value), else: System.delete_env(name)
    end)

    on_exit(fn ->
      Enum.each(previous, fn {name, value} ->
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end)
    end)

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    saved = System.get_env("SUBSCRIPTION_WEBHOOK_SECRET")
    System.delete_env("SUBSCRIPTION_WEBHOOK_SECRET")

    on_exit(fn ->
      if saved,
        do: System.put_env("SUBSCRIPTION_WEBHOOK_SECRET", saved),
        else: System.delete_env("SUBSCRIPTION_WEBHOOK_SECRET")
    end)

    :ok
  end

  for kase <- (@path |> File.read!() |> Jason.decode!())["cases"] do
    @kase kase
    @tag golden_case: String.to_atom(kase["name"])
    @tag mutation: "M-C1-account-#{kase["name"]}"
    @tag api_now: %{elem(DateTime.from_iso8601(kase["source_time"]), 1) | microsecond: {0, 6}}
    @tag api_repo:
           if(kase["name"] == "otp_destroy_second_save_failure",
             do: __MODULE__.ClearValidationFailure,
             else: Repo
           )
    test "golden #{kase["name"]}", ctx do
      rows("TRUNCATE #{Enum.join(@tables, ",")} CASCADE")
      Repo.query!("TRUNCATE #{Enum.join(@tables, ",")} CASCADE")

      for {name, value} <- @kase["env"] do
        if is_nil(value),
          do: System.delete_env(name),
          else:
            System.put_env(name, if(value == "runtime:webhook_secret", do: @webhook, else: value))
      end

      if String.ends_with?(@kase["name"], "_unavailable"),
        do: System.delete_env("OTP_ENCRYPTION_PRIMARY_KEY")

      for [table, seeds] <- ctx.fixture["setups"][@kase["setup"]], row <- seeds do
        assert table in @tables
        hydrated = seed(row, ctx)
        ApiGolden.insert!(table, hydrated, ScratchRepo)
        ApiGolden.insert!(table, hydrated)
      end

      for {key, _} <- @kase["cache_after"] || %{}, do: Dawarich.Redis.cache_command(["DEL", key])
      before = after_rows(Repo)
      before_scratch = after_rows(ScratchRepo)

      options =
        if @kase["runtime_crypto"] && @kase["expect"] == "own",
          do: crypto_options(@kase, before),
          else: []

      ApiGolden.check(request(@kase), ctx.port, ctx.upstream, options)

      expected =
        if @kase["expect"] == "own",
          do: expected_after(@kase, before, ctx),
          else: before

      assert after_rows(Repo) == expected
      assert after_rows(ScratchRepo) == before_scratch
      assert rows("SELECT kind,payload FROM phoenix.rails_commands") == []

      for {key, _} <- @kase["cache_after"] || %{} do
        assert Dawarich.RailsCache.get(key) == :miss
        assert Dawarich.Redis.cache_command(["TTL", key]) == {:ok, -2}
      end
    end
  end

  defp seed(row, ctx) do
    Map.new(row, fn
      {key, "runtime:password_digest"} ->
        {key, ctx.password_digest}

      {key, "runtime:encrypted_otp_secret"} ->
        {key, ctx.encrypted_otp}

      {"otp_backup_codes", values} when is_list(values) ->
        {"otp_backup_codes", Enum.map(values, fn _ -> ctx.backup_digest end)}

      pair ->
        pair
    end)
  end

  defp prepare(name, ctx) do
    kase = Enum.find(ctx.fixture["cases"], &(&1["name"] == name)) |> Map.put("expect", "own")
    Repo.query!("TRUNCATE #{Enum.join(@tables, ",")} CASCADE")

    for [table, seeds] <- ctx.fixture["setups"][kase["setup"]], row <- seeds do
      ApiGolden.insert!(table, seed(row, ctx))
    end

    {kase, after_rows(Repo)}
  end

  defp crypto_options(kase, before) do
    [
      crypto: fn raw ->
        validate_crypto!(kase, raw, before)
        crypto_body(kase, raw)
      end
    ]
  end

  defp validate_crypto!(kase, raw, before) do
    payload = Jason.decode!(raw)
    user = Repo.get!(Dawarich.Auth.Account, 954_001)
    prior = Enum.find(before["users"], &(&1["id"] == user.id))

    if kase["runtime_crypto"] == "setup" do
      secret = payload["secret"]
      assert is_binary(secret) and Regex.match?(~r/\A[A-Z2-7]{32}\z/, secret)
      assert Secret.decrypt(user.otp_secret) == {:ok, secret}
      assert payload["provisioning_uri"] == Totp.provisioning_uri(secret, user.email)
      assert user.otp_secret != prior["otp_secret"]
    else
      codes = payload["backup_codes"]
      assert length(codes) == 10 and length(Enum.uniq(codes)) == 10
      assert length(user.otp_backup_codes) == 10
      assert Enum.all?(codes, &Regex.match?(~r/\A[0-9a-f]{24}\z/, &1))

      compatible =
        Enum.all?(Enum.zip(codes, user.otp_backup_codes), fn {code, hash} ->
          Bcrypt.verify_pass(code, hash)
        end)

      assert compatible

      assert MapSet.disjoint?(
               MapSet.new(user.otp_backup_codes),
               MapSet.new(prior["otp_backup_codes"] || [])
             )

      assert BackupCodes.consume(user.otp_backup_codes, @backup) == :invalid
      assert {:ok, remaining} = BackupCodes.consume(user.otp_backup_codes, hd(codes))
      assert BackupCodes.consume(remaining, hd(codes)) == :invalid
    end
  end

  defp crypto_body(kase, raw) do
    if kase["runtime_crypto"] == "setup" do
      secret = Jason.decode!(raw)["secret"]
      String.replace(raw, secret, "runtime:otp_secret")
    else
      Enum.reduce(
        Jason.decode!(raw)["backup_codes"],
        raw,
        &String.replace(&2, &1, "runtime:backup_code")
      )
    end
  end

  defp expected_after(kase, before, ctx) do
    actual = after_rows(Repo)

    Map.new(kase["after"], fn {table, rows} ->
      expected =
        Enum.map(rows, fn row ->
          current = Enum.find(actual[table], &(&1["id"] == row["id"]))
          prior = Enum.find(before[table], &(&1["id"] == row["id"]))

          Map.new(row, fn
            {"otp_secret", "runtime:encrypted_otp_secret"} ->
              if kase["runtime_crypto"] == "setup" and row["id"] == 954_001,
                do: assert(current["otp_secret"] != prior["otp_secret"]),
                else: assert(current["otp_secret"] == prior["otp_secret"])

              {"otp_secret", current["otp_secret"]}

            {"otp_backup_codes", values} when is_list(values) and values != [] ->
              if kase["runtime_crypto"] in ["backup", "confirm"] and row["id"] == 954_001,
                do: assert(current["otp_backup_codes"] != prior["otp_backup_codes"]),
                else: assert(current["otp_backup_codes"] == prior["otp_backup_codes"])

              assert length(current["otp_backup_codes"]) == length(values)
              {"otp_backup_codes", current["otp_backup_codes"]}

            pair ->
              seed(Map.new([pair]), ctx) |> Enum.at(0)
          end)
        end)

      {table, expected}
    end)
  end

  defp request(kase) do
    body =
      kase["request"]["body"]
      |> String.replace(
        "runtime:password",
        if(get_in(kase, ["runtime_request", "password"]) == "wrong", do: "wrong", else: @password)
      )
      |> String.replace("runtime:current", current_code(kase))
      |> String.replace("runtime:backup", @backup)

    headers =
      for [name, value] <- kase["request"]["headers"],
          String.downcase(name) != "content-length",
          do: [name, String.replace(value, "runtime:webhook_secret", @webhook)]

    headers =
      if body != "",
        do: headers ++ [["Content-Length", to_string(byte_size(body))]],
        else: headers

    put_in(kase, ["request"], %{kase["request"] | "headers" => headers, "body" => body})
  end

  defp current_code(kase) do
    {:ok, time, _} =
      DateTime.from_iso8601(
        get_in(kase, ["runtime_request", "otp_code_at"]) || kase["source_time"]
      )

    Totp.at("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP", DateTime.to_unix(time))
  end

  defp after_rows(repo) do
    if repo == Repo, do: repo.query!("SELECT set_config('TimeZone','UTC',true)")

    Map.new(@tables, fn table ->
      data =
        repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id", [], log: false).rows

      {table, Enum.map(data, fn [text] -> Jason.decode!(text) end)}
    end)
  end
end
