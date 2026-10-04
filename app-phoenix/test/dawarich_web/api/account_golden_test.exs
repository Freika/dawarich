defmodule DawarichWeb.Api.AccountGoldenTest do
  use Dawarich.ApiEndpointCase
  use Dawarich.JobsCase, async: false

  alias Dawarich.Test.ApiGolden
  alias Dawarich.ActiveRecordEncryption

  @path "test/fixtures/api_account/golden.json"
  @moduletag api_public_only: true
  @moduletag :capture_log
  @tables ~w(users families family_memberships instance_settings)
  @password "a4rest-account-synthetic-password"
  @backup "a4rest-account-synthetic-backup"
  @webhook "a4rest-account-synthetic-webhook"

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
    test "golden #{kase["name"]}", ctx do
      rows("TRUNCATE #{Enum.join(@tables, ",")} CASCADE")
      Repo.query!("TRUNCATE #{Enum.join(@tables, ",")} CASCADE")

      for {name, value} <- @kase["env"] do
        if is_nil(value),
          do: System.delete_env(name),
          else:
            System.put_env(name, if(value == "runtime:webhook_secret", do: @webhook, else: value))
      end

      for [table, seeds] <- ctx.fixture["setups"][@kase["setup"]], row <- seeds do
        assert table in @tables
        hydrated = seed(row, ctx)
        ApiGolden.insert!(table, hydrated, ScratchRepo)
        ApiGolden.insert!(table, hydrated)
      end

      for {key, _} <- @kase["cache_after"] || %{}, do: Dawarich.Redis.cache_command(["DEL", key])
      before = after_rows(Repo)
      before_scratch = after_rows(ScratchRepo)
      ApiGolden.check(request(@kase), ctx.port, ctx.upstream)

      expected =
        if @kase["expect"] == "own",
          do:
            Map.new(@kase["after"], fn {table, rows} ->
              {table, Enum.map(rows, &seed(&1, ctx))}
            end),
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

  defp request(kase) do
    body =
      kase["request"]["body"]
      |> String.replace(
        "runtime:password",
        if(get_in(kase, ["runtime_request", "password"]) == "wrong", do: "wrong", else: @password)
      )
      |> String.replace("runtime:current", "123456")
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

  defp after_rows(repo) do
    if repo == Repo, do: repo.query!("SELECT set_config('TimeZone','UTC',true)")

    Map.new(@tables, fn table ->
      data =
        repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id", [], log: false).rows

      {table, Enum.map(data, fn [text] -> Jason.decode!(text) end)}
    end)
  end
end
