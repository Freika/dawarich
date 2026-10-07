defmodule Dawarich.Cloud.SessionConnection do
  @moduledoc false

  @options ~w(hostname endpoints port username password database socket_dir socket socket_options ssl ssl_opts types parameters target_server_type connect_timeout handshake_timeout ping_timeout timeout prepare transactions)a

  def check(repo, opts \\ []) do
    config = repo.config()

    url =
      opts[:session_url] || config[:session_url] ||
        Application.get_env(:dawarich, :database_session_url) ||
        System.get_env("DATABASE_SESSION_URL")

    direct = if url in [nil, ""], do: config, else: direct_config(config, url)
    mode = direct[:pool_mode] || direct[:pooling_mode]
    ports = Enum.map(direct[:endpoints] || [], &elem(&1, 1))

    if direct[:port] == 6432 or 6432 in ports or
         mode in ["transaction", "statement", :transaction, :statement] or
         (url in [nil, ""] and
            System.get_env("DATABASE_POOLING_MODE") in ["transaction", "statement"]) do
      {:error, :session_connection_required}
    else
      {:ok, Keyword.take(direct, @options)}
    end
  rescue
    _ -> {:error, :session_connection_required}
  end

  defp direct_config(config, url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    parsed = Ecto.Repo.Supervisor.parse_url(url)
    parsed = Keyword.merge(Keyword.take(config, [:ssl, :ssl_opts, :types]), parsed)

    case query["sslmode"] do
      nil ->
        parsed

      "disable" ->
        Keyword.put(parsed, :ssl, false)

      "require" ->
        Keyword.put(parsed, :ssl, verify: :verify_none)

      mode when mode in ["verify-ca", "verify-full"] ->
        ssl = [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          server_name_indication: String.to_charlist(uri.host),
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]

        ssl =
          if cert = System.get_env("PGSSLROOTCERT"),
            do:
              ssl
              |> Keyword.delete(:cacerts)
              |> Keyword.put(:cacertfile, String.to_charlist(cert)),
            else: ssl

        Keyword.put(parsed, :ssl, ssl)

      _ ->
        raise ArgumentError, "unsupported session TLS mode"
    end
  end

  def with_connection(repo, opts, fun) do
    with {:ok, config} <- check(repo, opts),
         {:ok, conn} <- Postgrex.start_link(config ++ [backoff_type: :stop, max_restarts: 0]) do
      try do
        %{rows: [[database]]} = Postgrex.query!(conn, "SELECT current_database()::text", [])
        [[expected]] = repo.query!("SELECT current_database()::text", [], log: false).rows

        if database == expected,
          do: fun.(conn, database),
          else: {:error, :session_database_mismatch}
      after
        if Process.alive?(conn), do: GenServer.stop(conn)
      end
    else
      _ -> {:error, :session_connection_required}
    end
  end

  def with_migration_lock(repo, opts, fun) do
    with_connection(repo, opts, fn conn, database ->
      key = 2_053_462_845 * :erlang.crc32(database)
      deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :lease_wait_ms, 900_000)

      with :ok <- acquire(conn, key, opts, deadline) do
        Postgrex.query!(conn, "SELECT pg_advisory_lock($1)", [key])

        try do
          fun.()
        after
          if Postgrex.query!(conn, "SELECT pg_advisory_unlock($1), pg_advisory_unlock($1)", [key]).rows !=
               [[true, true]],
             do: raise("migration session lock lost")
        end
      end
    end)
  end

  def with_callback_lock(repo, event, fun) do
    with_connection(repo, [], fn conn, _ ->
      Postgrex.query!(conn, "SELECT pg_advisory_lock(hashtextextended($1,0))", [event])

      try do
        fun.()
      after
        if Postgrex.query!(conn, "SELECT pg_advisory_unlock(hashtextextended($1,0))", [event]).rows !=
             [[true]],
           do: raise("callback session lock lost")
      end
    end)
  end

  defp acquire(conn, key, opts, deadline) do
    case Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [key]).rows do
      [[true]] ->
        :ok

      [[false]] ->
        if System.monotonic_time(:millisecond) >= deadline do
          {:error, :migration_lock_busy}
        else
          Keyword.get(opts, :lease_sleep, &Process.sleep/1).(
            Keyword.get(opts, :lease_poll_ms, 2_000)
          )

          acquire(conn, key, opts, deadline)
        end
    end
  end
end
