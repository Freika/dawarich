defmodule Dawarich.ApiProtocolClearFailure do
  defdelegate one(query, opts), to: Dawarich.Repo
  defdelegate query!(sql, params, opts), to: Dawarich.Repo

  def update!(changeset, opts) do
    if Map.has_key?(changeset.changes, :otp_secret) and is_nil(changeset.changes.otp_secret),
      do: raise("A4 OTP expected clear failure"),
      else: Dawarich.Repo.update!(changeset, opts)
  end
end

defmodule Dawarich.Auth.ApiProtocol do
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.TwoFactor.{Api, Totp}
  alias Dawarich.Repo

  @auth_ids [911_510_001, 911_510_002, 911_510_003, 911_510_004]
  @auth_fields ~w(id email encrypted_password api_key settings otp_secret otp_backup_codes otp_required_for_login consumed_timestep failed_otp_attempts otp_locked_at failed_attempts sign_in_count)

  def password_work(path, context) do
    refute_auth_file(path)
    id = 911_510_010
    email = "a11f-password-work@example.invalid"

    [[0]] =
      Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

    hash =
      Bcrypt.hash_pwd_salt("safepassword12", Keyword.take(Map.to_list(context), [:log_rounds]))

    cost = hash |> String.split("$") |> Enum.at(2) |> String.to_integer()
    low_hash = Bcrypt.hash_pwd_salt("safepassword12", log_rounds: 4)

    fields =
      ~w(id email encrypted_password api_key settings provider deleted_at status plan subscription_source active_until otp_required_for_login)

    stamp = NaiveDateTime.utc_now()

    Dawarich.Test.SeedIds.insert_all!(
      Repo,
      "users",
      [
        %{
          id: id,
          email: email,
          encrypted_password: hash,
          api_key: :crypto.hash(:sha256, email) |> Base.encode16(case: :lower),
          settings: %{},
          subscription_source: 0,
          active_until: nil,
          status: 1,
          plan: 1,
          theme: "dark",
          created_at: stamp,
          updated_at: stamp
        }
      ],
      log: false
    )

    hash_cases =
      for minor <- ~w(2a 2b 2x 2y), cost <- ~w(00 01 02 03 32 99) do
        hash = "$" <> minor <> "$" <> cost <> "$" <> binary_part(low_hash, 7, 53)
        {"uncomputable-#{minor}-#{cost}", %{encrypted_password: hash}}
      end

    hash_cases =
      hash_cases ++
        for minor <- ~w(2z 1a) do
          {"uncomputable-#{minor}",
           %{encrypted_password: "$" <> minor <> "$04$" <> binary_part(low_hash, 7, 53)}}
        end

    try do
      rows =
        for {name, changes} <-
              [
                {"known-wrong", %{}},
                {"known-wrong-low-cost", %{encrypted_password: low_hash}},
                {"known-wrong-2a-low-cost",
                 %{encrypted_password: String.replace_prefix(low_hash, "$2b$", "$2a$")}},
                {"rejected-2a-low-cost",
                 %{
                   provider: "openid_connect",
                   encrypted_password: String.replace_prefix(low_hash, "$2b$", "$2a$")
                 }},
                {"rejected-2y-low-cost",
                 %{encrypted_password: String.replace_prefix(low_hash, "$2b$", "$2y$")}},
                {"rejected-2x-low-cost",
                 %{encrypted_password: String.replace_prefix(low_hash, "$2b$", "$2x$")}},
                {"wrong-nul-known", %{encrypted_password: low_hash}},
                {"wrong-nul-unknown", %{}},
                {"wrong-nul-deleted", %{deleted_at: DateTime.utc_now()}},
                {"correct-nul", %{encrypted_password: low_hash}},
                {"correct-nul-otp",
                 %{encrypted_password: low_hash, otp_required_for_login: true}},
                {"wrong-nul-form", %{encrypted_password: low_hash}},
                {"correct-nul-form", %{encrypted_password: low_hash}},
                {"unicode-known", %{email: "päss@example.invalid", encrypted_password: low_hash}},
                {"unicode-unknown", %{}},
                {"unicode-deleted",
                 %{email: "päss@example.invalid", deleted_at: DateTime.utc_now()}},
                {"unknown", %{}},
                {"deleted", %{deleted_at: DateTime.utc_now()}},
                {"blank-hash", %{encrypted_password: ""}},
                {"provider", %{provider: "openid_connect"}},
                {"provider-low-cost",
                 %{provider: "openid_connect", encrypted_password: low_hash}},
                {"settings", %{settings: %{"maps" => 1}}},
                {"settings-low-cost", %{settings: %{"maps" => 1}, encrypted_password: low_hash}},
                {"metadata", %{plan: 99}},
                {"metadata-low-cost", %{plan: 99, encrypted_password: low_hash}},
                {"validation", %{email: "a11f-password-work"}},
                {"validation-low-cost",
                 %{email: "a11f-password-work", encrypted_password: low_hash}}
              ] ++ hash_cases ++ [{"invalid-hash", %{encrypted_password: "invalid"}}] do
          user = Repo.get!(Account, id, log: false)
          Repo.update!(Ecto.Changeset.change(user, changes), log: false)

          [[before]] =
            Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows

          submitted =
            if name == "unicode-unknown",
              do: "päss-unknown@example.invalid",
              else:
                if(name in ["unknown", "wrong-nul-unknown"],
                  do: "a11f-password-unknown@example.invalid",
                  else: before["email"]
                )

          password =
            if String.starts_with?(name, "correct-nul"),
              do: "safepassword12" <> <<0>> <> "suffix",
              else: "a11f-wrong-password"

          password =
            if String.starts_with?(name, "wrong-nul"),
              do: password <> <<0>> <> "suffix",
              else: password

          form? = String.ends_with?(name, "-form")

          raw =
            if form?,
              do: URI.encode_query(%{"email" => submitted, "password" => password}),
              else: Jason.encode!(%{"email" => submitted, "password" => password})

          type = if form?, do: "application/x-www-form-urlencoded", else: "application/json"

          conn =
            Plug.Test.conn("POST", "http://www.example.com/api/v1/auth/login", raw)
            |> Plug.Conn.put_req_header("content-type", type)
            |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(raw)))
            |> Plug.Conn.put_req_header("accept", "application/json")

          {result, {work, lookups}} =
            password_trace(fn ->
              DawarichWeb.AuthApi.Http.call(conn,
                enabled: true,
                context: context,
                fallback: fn replay ->
                  Plug.Conn.put_private(replay, :password_work_replay, true)
                end
              )
            end)

          [[after_state]] =
            Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows

          unless before == after_state and result.halted and
                   result.private[:password_work_replay] == true and
                   result.private[:dawarich_raw_body] == raw,
                 do: raise("API password work #{name} changed state or replay bytes")

          current = Repo.get!(Account, id, log: false)

          Repo.update!(
            Ecto.Changeset.change(current, Map.take(Map.from_struct(user), Map.keys(changes))),
            log: false
          )

          %{
            "name" => name,
            "raw" => raw,
            "native_work" => work,
            "native_lookups" => lookups,
            "type" => type,
            "state" => Map.take(before, fields)
          }
        end

      payload = %{
        "mode" => "api_auth_password_work",
        "id" => id,
        "email" => email,
        "dummy_cost" => cost,
        "rows" => rows
      }

      File.write!(path, "", [:exclusive])
      File.chmod!(path, 0o600)
      File.write!(path, Jason.encode!(payload))
    after
      Repo.query!("DELETE FROM users WHERE id=$1", [id], log: false)
    end
  end

  def otp_work(path, context) do
    alias Dawarich.Auth.Api.ChallengeToken
    alias Dawarich.Auth.TwoFactor.Secret
    refute_auth_file(path)
    context = auth_context(context)

    env =
      Map.put(
        context.env,
        "JWT_SECRET_KEY",
        :crypto.hash(:sha256, "a11f otp work signing") |> Base.encode16(case: :lower)
      )

    context = Map.put(context, :env, env)
    id = 911_510_011
    email = "a11f-otp-work@example.invalid"
    now = context.clock.()
    secret = Totp.generate_secret("a11f otp work entropy")
    {:ok, ciphertext} = Secret.encrypt(secret, context.env)
    hash = Bcrypt.hash_pwd_salt("safepassword12", log_rounds: 4)
    {:ok, token} = ChallengeToken.issue(id, context)

    [[0]] =
      Repo.query!("SELECT count(*) FROM users WHERE id=$1 OR email=$2", [id, email], log: false).rows

    Dawarich.Test.RailsUser.insert!(%{
      id: id,
      email: email,
      encrypted_password: hash,
      api_key: :crypto.hash(:sha256, email) |> Base.encode16(case: :lower),
      settings: %{},
      subscription_source: 0,
      active_until: nil,
      otp_secret: ciphertext,
      otp_required_for_login: true,
      otp_backup_codes: [hash, hash],
      failed_otp_attempts: 3
    })

    cases = [
      {"supported-wrong", %{}, "wrong", ["totp", "totp", "totp", 4, 4]},
      {"provider-wrong", %{provider: "openid_connect"}, "wrong", ["totp", "totp", "totp", 4, 4]},
      {"legacy-wrong", %{otp_backup_codes: [String.replace_prefix(hash, "$2b$", "$2y$"), hash]},
       "wrong", ["totp", "totp", "totp", 4, 4]},
      {"nil-secret", %{otp_secret: nil}, "wrong", [4, 4]},
      {"blank-secret", %{otp_secret: elem(Secret.encrypt("", context.env), 1)}, "wrong", [4, 4]},
      {"unreadable-secret", %{otp_secret: "unreadable"}, "wrong", []},
      {"invalid-secret", %{otp_secret: elem(Secret.encrypt("!", context.env), 1)}, "wrong", []},
      {"disabled", %{otp_required_for_login: false}, "wrong", ["totp", "totp", "totp", 4, 4]},
      {"locked-provider", %{provider: "openid_connect", otp_locked_at: now}, "wrong", [4, 4]},
      {"locked-unreadable", %{otp_secret: "unreadable", otp_locked_at: now}, "wrong", [4, 4]},
      {"provider-totp", %{provider: "openid_connect"}, Totp.at(secret, DateTime.to_unix(now)),
       ["totp", "totp", "totp"]},
      {"provider-backup", %{provider: "openid_connect"}, "safepassword12",
       ["totp", "totp", "totp", 4]},
      {"legacy-backup", %{otp_backup_codes: [String.replace_prefix(hash, "$2b$", "$2y$"), hash]},
       "safepassword12", ["totp", "totp", "totp", 4]},
      {"nil-secret-backup", %{otp_secret: nil}, "safepassword12", [4]},
      {"settings", %{settings: %{"maps" => 1}}, "wrong", ["totp", "totp", "totp", 4, 4]},
      {"missing-encryption-setting", %{}, "wrong", ["totp", "totp", "totp", 4, 4]}
    ]

    cases =
      cases ++
        for cost <- ~w(00 01 02 03) do
          bad = "$2y$" <> cost <> "$" <> binary_part(hash, 7, 53)

          {"uncomputable-backup-#{cost}", %{otp_backup_codes: [bad, hash]}, "wrong",
           ["totp", "totp", "totp", 4]}
        end

    cases =
      cases ++
        [
          {"nil-backup", %{otp_backup_codes: [nil, hash]}, "wrong", ["totp", "totp", "totp", 4]},
          {"invalid-backup", %{otp_backup_codes: ["invalid", hash]}, "wrong",
           ["totp", "totp", "totp"]},
          {"password-state", %{encrypted_password: "invalid"}, "wrong",
           ["totp", "totp", "totp", 4, 4]}
        ]

    try do
      rows =
        for {name, changes, code, expected} <- cases do
          row_context =
            if name == "missing-encryption-setting",
              do: %{context | env: Map.put(context.env, "OTP_ENCRYPTION_DETERMINISTIC_KEY", nil)},
              else: context

          user = Repo.get!(Account, id, log: false)
          Repo.update!(Ecto.Changeset.change(user, changes), log: false)

          [[before]] =
            Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows

          raw = Jason.encode!(%{"challenge_token" => token, "otp_code" => code})

          conn =
            Plug.Test.conn("POST", "http://www.example.com/api/v1/auth/otp_challenge", raw)
            |> Plug.Conn.put_req_header("content-type", "application/json")
            |> Plug.Conn.put_req_header("content-length", Integer.to_string(byte_size(raw)))
            |> Plug.Conn.put_req_header("accept", "application/json")

          {result, {work, _}} =
            password_trace(fn ->
              DawarichWeb.AuthApi.Http.call(conn,
                enabled: true,
                context: row_context,
                fallback: fn replay -> Plug.Conn.put_private(replay, :otp_work_replay, true) end
              )
            end)

          [[after_state]] =
            Repo.query!("SELECT to_jsonb(users) FROM users WHERE id=$1", [id], log: false).rows

          unless before == after_state and result.halted and
                   result.private[:otp_work_replay] == true and
                   result.private[:dawarich_raw_body] == raw,
                 do: raise("API OTP work #{name} changed state or failed replay")

          current = Repo.get!(Account, id, log: false)

          Repo.update!(
            Ecto.Changeset.change(current, Map.take(Map.from_struct(user), Map.keys(changes))),
            log: false
          )

          %{
            "name" => name,
            "state" => Map.take(before, @auth_fields ++ ~w(provider)),
            "code" => code,
            "native_work" => work,
            "expected_work" => expected,
            "env" => row_context.env
          }
        end

      out_of_range_tokens =
        for id <- [9_223_372_036_854_775_808, 18_446_744_073_709_551_616] do
          {:ok, token} = ChallengeToken.issue(id, context)
          token
        end

      payload = %{
        "mode" => "api_auth_otp_work",
        "out_of_range_tokens" => out_of_range_tokens,
        "id" => id,
        "email" => email,
        "rows" => rows,
        "token" => token,
        "env" => context.env,
        "rails_secret" => context[:rails_secret],
        "at" => DateTime.to_unix(now)
      }

      File.write!(path, "", [:exclusive])
      File.chmod!(path, 0o600)
      File.write!(path, Jason.encode!(payload))
    after
      Repo.query!("DELETE FROM users WHERE id=$1 AND email=$2", [id, email], log: false)
    end
  end

  defp password_trace(fun) do
    tracer = spawn(fn -> password_calls([], 0) end)

    calls = [
      {Bcrypt, :verify_pass, 2},
      {Bcrypt.Base, :hash_password, 2},
      {:crypto, :mac, 4},
      {Dawarich.Auth.Api.Actor, :for_password, 2}
    ]

    for {module, _, _} <- calls, do: Code.ensure_loaded!(module)
    for call <- calls, do: :erlang.trace_pattern(call, true, [:local])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      result = fun.()
      :erlang.trace(self(), false, [:call])
      ref = :erlang.trace_delivered(self())
      receive do: ({:trace_delivered, _, ^ref} -> :ok)
      send(tracer, {:work, self(), ref})
      receive do: ({:work, ^ref, work} -> {result, work})
    after
      :erlang.trace(self(), false, [:call])
      for call <- calls, do: :erlang.trace_pattern(call, false, [:local])
      Process.exit(tracer, :kill)
    end
  end

  defp password_calls(work, lookups) do
    receive do
      {:trace, _, :call, {:crypto, :mac, [:hmac, :sha, _, _]}} ->
        password_calls(work ++ ["totp"], lookups)

      {:trace, _, :call, {:crypto, :mac, _}} ->
        password_calls(work, lookups)

      {:trace, _, :call, {Bcrypt, :verify_pass, [_, hash]}} ->
        password_calls(
          work ++ [hash |> String.split("$") |> Enum.at(2) |> String.to_integer()],
          lookups
        )

      {:trace, _, :call, {Bcrypt.Base, :hash_password, [_, salt]}} ->
        password_calls(
          work ++ [salt |> to_string() |> String.split("$") |> Enum.at(2) |> String.to_integer()],
          lookups
        )

      {:trace, _, :call, {Dawarich.Auth.Api.Actor, :for_password, _}} ->
        password_calls(work, lookups + 1)

      {:work, owner, ref} ->
        send(owner, {:work, ref, {work, lookups}})
    end
  end

  def auth_write(path, supplied, lifecycle) when lifecycle in ["projection", "shared_rdb"] do
    alias Dawarich.Auth.Api.{Challenge, ChallengeToken, ChallengeWrite}
    alias Dawarich.Auth.TwoFactor.Secret
    refute_auth_file(path)
    auth_absent!()
    context = auth_context(supplied)
    now = context.clock.()
    secret = Totp.generate_secret("a11f protocol entropy")
    {:ok, ciphertext} = Secret.encrypt(secret, context.env)
    hash = Bcrypt.hash_pwd_salt("safepassword12", log_rounds: 4)

    backups =
      Enum.map(["a11f backup one", "a11f backup two"], &Bcrypt.hash_pwd_salt(&1, log_rounds: 4))

    Process.put(:a11f_protocol_keys, [])

    try do
      rows =
        for id <- @auth_ids do
          %{
            id: id,
            email: auth_email(id),
            encrypted_password: hash,
            api_key:
              :crypto.hash(:sha256, "a11f protocol actor #{id}") |> Base.encode16(case: :lower),
            status: 1,
            plan: 1,
            subscription_source: 0,
            active_until: nil,
            settings: %{},
            otp_secret: ciphertext,
            otp_backup_codes: backups,
            otp_required_for_login: true,
            failed_otp_attempts: if(id == List.last(@auth_ids), do: 9, else: 3),
            failed_attempts: 7,
            sign_in_count: 9,
            created_at: DateTime.to_naive(now),
            updated_at: DateTime.to_naive(now)
          }
        end

      {4, _} = Dawarich.Test.SeedIds.insert_all!(Repo, "users", rows, log: false)

      actors =
        for {id, index} <- Enum.with_index(@auth_ids) do
          {:ok, token} = ChallengeToken.issue(id, context)
          {:ok, claims} = ChallengeToken.verify(token, context)
          key = "otp_challenge:consumed:" <> claims["jti"]
          Process.put(:a11f_protocol_keys, Process.get(:a11f_protocol_keys) ++ [key])

          if index == 0 do
            {:ok, prepared} =
              Challenge.prepare(token, Totp.at(secret, DateTime.to_unix(now)), context)

            {:ok, _} = ChallengeWrite.commit(prepared, context)
          end

          %{
            "id" => id,
            "email" => auth_email(id),
            "token" => token,
            "jti" => claims["jti"],
            "state" => auth_state(id)
          }
        end

      payload = %{
        "mode" => "api_auth",
        "lifecycle" => lifecycle,
        "at" => DateTime.to_unix(now),
        "env" => context.env,
        "secret" => secret,
        "actors" => actors,
        "marker_keys" => Process.get(:a11f_protocol_keys)
      }

      File.write!(path, "", [:exclusive])
      File.chmod!(path, 0o600)
      File.write!(path, Jason.encode!(payload))
      if lifecycle == "projection", do: auth_delete!()
    rescue
      error ->
        auth_cleanup(context)
        if File.exists?(path), do: File.rm!(path)
        reraise error, __STACKTRACE__
    end
  end

  def auth_source(path, supplied, lifecycle) do
    alias Dawarich.Auth.Api.{Challenge, ChallengeCache, ChallengeToken, ChallengeWrite}
    payload = Jason.decode!(File.read!(path))

    unless payload["mode"] == "api_auth" and payload["lifecycle"] == lifecycle and
             Enum.map(payload["actors"], & &1["id"]) == @auth_ids and
             Enum.map(payload["actors"], & &1["email"]) == Enum.map(@auth_ids, &auth_email/1) and
             Bitwise.band(File.stat!(path).mode, 0o777) == 0o600,
           do: raise("A11f owned private payload required")

    context = auth_context(Map.put(supplied, :env, payload["env"]))

    context =
      Map.put(context, :clock, fn ->
        DateTime.from_unix!((payload["at"] + 30) * 1_000_000, :microsecond)
      end)

    Process.put(:a11f_protocol_keys, payload["marker_keys"] ++ payload["rails"]["marker_keys"])

    try do
      if lifecycle == "shared_rdb" do
        auth_continuity!(payload["rails"]["actors"])

        IO.puts(
          "API auth shared RDB retains the same live actors and markers across runtimes: PASS"
        )
      else
        auth_absent!()
        for actor <- payload["rails"]["actors"], do: auth_insert_state!(actor["state"])
      end

      for actor <- Enum.take(payload["actors"], 3) do
        {:replay, _} =
          Challenge.prepare(
            actor["token"],
            Totp.at(payload["secret"], payload["at"] + 30),
            context
          )

        {:ok, true} = ChallengeCache.exists?(actor["jti"], context)
      end

      for {actor, index} <- Enum.with_index(payload["rails"]["actors"] |> tl()) do
        {:ok, _} = ChallengeToken.verify(actor["token"], context)

        code =
          if index == 0,
            do: Totp.at(payload["secret"], payload["at"] + 30),
            else: "a11f backup two"

        {:ok, prepared} = Challenge.prepare(actor["token"], code, context)
        {:ok, _} = ChallengeWrite.commit(prepared, context)
        {:replay, _} = Challenge.prepare(actor["token"], code, context)
        state = auth_state(actor["id"])

        {:ok, ttl} = context.cache_command.(["PTTL", "otp_challenge:consumed:" <> actor["jti"]])
        {:ok, bytes} = context.cache_command.(["GET", "otp_challenge:consumed:" <> actor["jti"]])
        {:ok, entry} = Dawarich.RailsCache.Wire.decode(bytes)

        unless ttl in 1..300_000 and entry.expires_at == payload["at"] + 330,
          do: raise("A11f source marker TTL mismatch")

        unless state["failed_otp_attempts"] == 0 and state["otp_locked_at"] == nil,
          do: raise("A11f source reset mismatch")

        expires = Map.put(context, :clock, fn -> DateTime.from_unix!(payload["at"] + 300) end)
        {:replay, _} = ChallengeToken.verify(actor["token"], expires)

        before_expiry =
          Map.put(context, :clock, fn -> DateTime.from_unix!(payload["at"] + 299) end)

        {:ok, _} = ChallengeToken.verify(actor["token"], before_expiry)
      end

      IO.puts("Phoenix accepts Rails-issued API challenges and rejects Rails-consumed JTIs: PASS")
    after
      auth_cleanup(context)
    end
  end

  def auth_continuity!(actors) do
    unless Enum.map(actors, & &1["id"]) == @auth_ids, do: raise("A11f actor ownership mismatch")

    for actor <- actors do
      unless actor["email"] == auth_email(actor["id"]) and
               auth_state(actor["id"]) == actor["state"],
             do:
               raise(
                 "API auth shared RDB retains the same live actors and markers across runtimes: state mismatch"
               )
    end
  end

  defp auth_context(context),
    do:
      Map.merge(
        %{
          self_hosted: true,
          oidc: false,
          timezone: "Etc/UTC",
          clock: fn -> ~U[2026-10-04 12:00:00.000000Z] end
        },
        context
      )

  defp auth_email(id), do: "a11f-protocol-#{id}@example.invalid"

  defp refute_auth_file(path),
    do: if(File.exists?(path), do: raise("A11f private payload already exists"))

  defp auth_absent! do
    [[0]] =
      Repo.query!(
        "SELECT count(*) FROM users WHERE id=ANY($1) OR email=ANY($2)",
        [@auth_ids, Enum.map(@auth_ids, &auth_email/1)],
        log: false
      ).rows
  end

  defp auth_state(id) do
    [[row]] =
      Repo.query!(
        "SELECT to_jsonb(users) FROM users WHERE id=$1 AND email=$2",
        [id, auth_email(id)],
        log: false
      ).rows

    Map.take(row, @auth_fields)
  end

  defp auth_insert_state!(state) do
    columns = Enum.join(@auth_fields, ",")
    fields = Enum.map_join(@auth_fields, ",", &"r.#{&1}")

    result =
      Repo.query!(
        "INSERT INTO users (#{columns}, status, plan, subscription_source, created_at, updated_at) SELECT #{fields}, 1, 1, 0, now(), now() FROM jsonb_populate_record(NULL::users,$1) r",
        [state],
        log: false
      )

    Dawarich.Test.SeedIds.advance!(Repo, "users", [state["id"]])
    result
  end

  defp auth_delete!,
    do:
      Repo.query!(
        "DELETE FROM users WHERE id=ANY($1) AND email=ANY($2)",
        [@auth_ids, Enum.map(@auth_ids, &auth_email/1)],
        log: false
      )

  defp auth_cleanup(context) do
    auth_delete!()
    for key <- Process.get(:a11f_protocol_keys, []), do: context.cache_command.(["DEL", key])
  end

  def write(path, env) do
    ids = [954_801, 954_802, 954_803]
    emails = Enum.map(ids, &"a4otp-protocol-#{&1}@example.invalid")
    now = ~U[2026-10-04 12:00:00.000000Z]
    password = "safepassword12"
    hash = Bcrypt.hash_pwd_salt(password, log_rounds: 4)

    context = %{
      self_hosted: true,
      env: env,
      clock: fn -> now end,
      backup_options: [log_rounds: 4]
    }

    projection = fn id ->
      actor = Repo.get!(Account, id, log: false)

      %{
        "enabled" => actor.otp_required_for_login,
        "ciphertext" => actor.otp_secret,
        "backups" => actor.otp_backup_codes,
        "consumed_timestep" => actor.consumed_timestep
      }
    end

    [[count]] =
      Repo.query!(
        "SELECT count(*) FROM users WHERE id=ANY($1) OR email=ANY($2)",
        [ids, emails],
        log: false
      ).rows

    unless count == 0, do: raise("A4 OTP synthetic actor already exists")

    rows =
      Enum.zip_with(ids, emails, fn id, email ->
        %{
          id: id,
          email: email,
          encrypted_password: hash,
          status: 1,
          plan: 1,
          settings: %{},
          api_key: "A4OTP_PROTOCOL_#{id}",
          created_at: now,
          updated_at: now
        }
      end)

    {3, _} = Dawarich.Test.SeedIds.insert_all!(Repo, "users", rows, log: false)

    try do
      actors =
        Enum.map(ids, fn id ->
          params = %{"password" => password}

          {secret, current, codes} =
            if id == 954_803 do
              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {nil, nil, codes}
            else
              {:ok, 200, {:object, setup}} = Api.run(:setup, id, params, context)
              secret = setup |> Map.new() |> Map.fetch!("secret")
              current = Totp.at(secret, DateTime.to_unix(now))

              {:ok, 200, {:object, [{"backup_codes", _}]}} =
                Api.run(:confirm, id, Map.put(params, "otp_code", current), context)

              {:ok, 200, {:object, [{"backup_codes", codes}]}} =
                Api.run(:backup_codes, id, params, context)

              {secret, current, codes}
            end

          confirmed = projection.(id)

          consumed =
            if id == 954_802 do
              try do
                Api.run(
                  :destroy,
                  id,
                  Map.put(params, "otp_code", current),
                  Map.put(context, :repo, Dawarich.ApiProtocolClearFailure)
                )

                raise "A4 OTP clear failure did not occur"
              rescue
                error in RuntimeError ->
                  unless error.message == "A4 OTP expected clear failure",
                    do: reraise(error, __STACKTRACE__)
              end

              projection.(id)
            else
              nil
            end

          {:ok, 200, _} = Api.run(:destroy, id, Map.put(params, "otp_code", hd(codes)), context)

          %{
            "id" => id,
            "email" => "a4otp-protocol-#{id}@example.invalid",
            "hash" => hash,
            "secret" => secret,
            "current_code" => current,
            "later_code" => if(secret, do: Totp.at(secret, DateTime.to_unix(now) + 30)),
            "unused_backup" => Enum.at(codes, 1),
            "confirmed" => confirmed,
            "consumed" => consumed,
            "disabled" => projection.(id)
          }
        end)

      result = %{
        "mode" => "api_two_factor_management",
        "schema" => 1,
        "summary" => "API storage only; no session issued",
        "password" => password,
        "at" => DateTime.to_unix(now),
        "actors" => actors
      }

      File.write!(path, Jason.encode!(result))
      File.chmod!(path, 0o600)
    after
      Repo.query!("DELETE FROM users WHERE id=ANY($1) AND email=ANY($2)", [ids, emails],
        log: false
      )
    end
  end
end
