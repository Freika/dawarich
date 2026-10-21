defmodule Dawarich.Release.CloudPreflight do
  @moduledoc false
  alias Dawarich.{ReleaseMigration, ReleaseMigrator, Redis}
  alias Dawarich.RailsCache.{Marshal, Wire}

  def check(repo, opts) do
    opts = Keyword.put(opts, :rails_lock_check, false)
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    with false <- ReleaseMigration.self_hosted?(env),
         false <- env["DAWARICH_CLOUD_DRAIN_ONLY"] == "true",
         :ok <- Dawarich.Cloud.Configuration.manager(env),
         {:ok, _} <- Dawarich.Cloud.SessionConnection.check(repo, opts),
         :ok <- schemas(repo),
         :ok <- ownership(repo),
         :ok <- extensions(repo),
         {:ok, state} <- ReleaseMigrator.status(repo, opts),
         :ok <- fresh?(repo, state),
         :ok <- private_versions(repo),
         {:ok, opts} <- registration(repo, opts) do
      {:ok, opts}
    else
      true -> {:error, :cloud_mode_required}
      error -> error
    end
  rescue
    _ -> {:error, :cloud_preflight_refused}
  catch
    _, _ -> {:error, :cloud_preflight_refused}
  end

  def private_paths do
    for {schema, directory} <- [{"phoenix", "migrations"}, {"oban", "oban_migrations"}],
        do: {schema, Application.app_dir(:dawarich, "priv/repo/" <> directory)}
  end

  def schemas_present?(repo) do
    repo.query!("SELECT 1 FROM pg_namespace WHERE nspname=ANY($1)", [~w(public phoenix oban)],
      log: false
    ).num_rows == 3
  end

  def schemas(repo) do
    rows =
      repo.query!(
        "SELECT nspname::text,(has_schema_privilege(current_user,oid,'USAGE') AND has_schema_privilege(current_user,oid,'CREATE')) FROM pg_namespace WHERE nspname=ANY($1) ORDER BY nspname",
        [~w(oban phoenix public)],
        log: false
      ).rows

    if rows == [["oban", true], ["phoenix", true], ["public", true]],
      do: :ok,
      else: {:error, :schema_permissions}
  end

  defp ownership(repo) do
    [[count]] =
      repo.query!(
        """
        SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname IN ('public','phoenix','oban') AND c.relkind IN ('r','p','S','v','m')
          AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')
          AND NOT pg_has_role(current_user,c.relowner,'USAGE')
        """,
        [],
        log: false
      ).rows

    if count == 0, do: :ok, else: {:error, :table_ownership}
  end

  defp extensions(repo) do
    [[count]] =
      repo.query!("SELECT count(*) FROM pg_extension WHERE extname IN ('postgis','pgcrypto')", [],
        log: false
      ).rows

    if count == 2, do: :ok, else: {:error, :extensions_required}
  end

  defp fresh?(repo, :fresh) do
    [[count]] =
      repo.query!(
        """
        SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='public' AND c.relkind IN ('r','p')
          AND c.relname NOT IN ('schema_migrations','ar_internal_metadata')
          AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_class'::regclass AND d.objid=c.oid AND d.deptype='e')
        """,
        [],
        log: false
      ).rows

    if count == 0, do: :ok, else: {:error, :unversioned_database}
  end

  defp fresh?(_repo, _state), do: :ok

  defp private_versions(repo) do
    if Enum.any?(private_paths(), fn {schema, path} ->
         if relation?(repo, schema <> ".phoenix_schema_migrations") do
           repo
           |> Ecto.Migrator.migrations(path,
             prefix: schema,
             skip_table_creation: true,
             migration_lock: false
           )
           |> Enum.any?(fn {_, _, name} -> name == "** FILE NOT FOUND **" end)
         else
           false
         end
       end),
       do: {:error, :newer_private_schema},
       else: :ok
  end

  defp registration(repo, opts) do
    if relation?(repo, "phoenix.registration_setting") and
         repo.query!("SELECT 1 FROM phoenix.registration_setting WHERE id=true", [], log: false).num_rows ==
           1 do
      {:ok, opts}
    else
      with {:ok, bytes} <- source(opts), :ok <- validate(bytes) do
        {:ok, Keyword.put(opts, :command, fn _ -> {:ok, bytes} end)}
      else
        _ -> {:error, :registration_copy_refused}
      end
    end
  end

  defp source(opts) do
    if command = opts[:command] do
      command.(["GET", "dawarich/registration_enabled"])
    else
      config = Application.fetch_env!(:dawarich, :redis)
      url = Keyword.fetch!(config, :url)

      options =
        Redis.options(url, config[:cache_database])
        |> Keyword.delete(:name)
        |> Keyword.put(:sync_connect, true)

      {:ok, conn} = Redix.start_link(url, options)

      try do
        Keyword.get(opts, :cache_command, &Redis.command/2).(
          ["GET", "dawarich/registration_enabled"],
          conn
        )
      after
        Redix.stop(conn)
      end
    end
  end

  defp validate(nil), do: :ok

  defp validate(bytes) do
    with :ok <- metadata(bytes),
         {:ok, %{value: value}} <- Wire.decode(bytes),
         true <- value in [true, false, nil],
         do: :ok
  end

  defp metadata(<<0, 17, _type, expires::little-float-64, -1::little-signed-32, _::binary>>)
       when expires < 0,
       do: :ok

  defp metadata(<<0, 17, _::binary>>), do: :error
  defp metadata(<<0, payload::binary>>), do: legacy(payload)
  defp metadata(<<1, payload::binary>>), do: legacy(:zlib.uncompress(payload))
  defp metadata(_), do: :error

  defp legacy(payload) do
    with {:ok, packed} when is_list(packed) and length(packed) <= 3 <- Marshal.decode(payload),
         nil <- Enum.at(packed, 1),
         nil <- Enum.at(packed, 2),
         do: :ok
  end

  defp relation?(repo, name),
    do: repo.query!("SELECT to_regclass($1) IS NOT NULL", [name], log: false).rows == [[true]]
end
