defmodule Dawarich.ReleaseMigration do
  @moduledoc false

  @type job :: {String.t(), list(), non_neg_integer()}
  @type step ::
          {String.t(), (module() -> term())} | {String.t(), (module() -> term()), keyword()}

  @callback release() :: String.t()
  @callback steps() :: [step()]
  @callback data_versions() :: [String.t()]

  defmodule UnportedEffect do
    defexception [:message]
  end

  @indexes_sql """
  SELECT i.relname,
         CASE WHEN 0 = ANY (d.indkey::int2[]) THEN NULL ELSE
           ARRAY(SELECT a.attname::text
                 FROM unnest(d.indkey::int2[]) WITH ORDINALITY AS k(attnum, ord)
                 JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum
                 WHERE k.ord <= d.indnkeyatts
                 ORDER BY k.ord)
         END
  FROM pg_class t
  JOIN pg_index d ON t.oid = d.indrelid
  JOIN pg_class i ON d.indexrelid = i.oid
  LEFT JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE i.relkind IN ('i', 'I') AND NOT d.indisprimary AND t.relname = $1
    AND n.nspname = ANY (current_schemas(false))
  """

  @index_name_sql """
  SELECT 1 FROM pg_class t
  JOIN pg_index d ON t.oid = d.indrelid
  JOIN pg_class i ON d.indexrelid = i.oid
  LEFT JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE i.relkind IN ('i', 'I') AND t.relname = $1 AND i.relname = $2
    AND n.nspname = ANY (current_schemas(false))
  """

  def normalize({version, fun}), do: {version, fun, true}
  def normalize({version, fun, opts}), do: {version, fun, Keyword.fetch!(opts, :transaction)}

  def versions(module), do: Enum.map(module.steps(), &elem(&1, 0))

  def sql!(repo, sql) do
    if not repo.in_transaction?() and statements(sql) > 1 do
      raise ArgumentError,
            "one statement per sql! outside a transaction: #{String.slice(sql, 0, 80)}"
    end

    repo.query!(sql, [], query_type: :text, log: false)
    :ok
  end

  def exists?(repo, sql, params \\ []) do
    %{rows: [[found]]} = repo.query!("SELECT EXISTS (#{sql})", params, log: false)

    found
  end

  def table?(repo, table) do
    exists?(
      repo,
      """
      SELECT 1 FROM pg_class c LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = ANY (current_schemas(false)) AND c.relname = $1
        AND c.relkind IN ('r', 'p')
      """,
      [table]
    )
  end

  def column?(repo, table, column) do
    exists?(
      repo,
      """
      SELECT 1 FROM pg_attribute
      WHERE attrelid = $1::text::regclass AND attname = $2 AND attnum > 0 AND NOT attisdropped
      """,
      [table, column]
    )
  end

  def index?(repo, table, opts) do
    opts = Keyword.validate!(opts, [:name, :columns])
    name = Keyword.get(opts, :name)
    columns = Keyword.get(opts, :columns)
    %{rows: rows} = repo.query!(@indexes_sql, [table], log: false)

    Enum.any?(rows, fn [index, index_columns] ->
      (is_nil(name) or index == name) and (is_nil(columns) or index_columns == columns)
    end)
  end

  def index_name?(repo, table, name), do: exists?(repo, @index_name_sql, [table, name])

  def with_lock_retry(repo, fun, opts) do
    outside_transaction!(repo, :with_lock_retry)
    lock_retry(repo, fun, Keyword.put_new(opts, :on, [:lock_not_available]), 1)
  end

  def rescue_sql(repo, fun, codes, fallback) do
    outside_transaction!(repo, :rescue_sql)

    try do
      fun.()
    rescue
      error in Postgrex.Error ->
        if codes == :any or error.postgres[:code] in codes,
          do: fallback.(error),
          else: reraise(error, __STACKTRACE__)
    end
  end

  def require_zero_lock_timeout!(repo) do
    %{rows: [[value]]} = repo.query!("SELECT current_setting('lock_timeout')", [], log: false)

    if value != "0" do
      raise "lock_timeout is #{value} for this database role; CREATE INDEX CONCURRENTLY needs 0. " <>
              "Run ALTER ROLE <role> SET lock_timeout = 0 or migrate without a connection pooler, then start again"
    end

    :ok
  end

  def job(class, args \\ [], wait_seconds \\ 0), do: {class, args, wait_seconds}

  def unported!(effect), do: raise(UnportedEffect, "#{effect} has no Phoenix port yet")

  def self_hosted? do
    System.get_env("SELF_HOSTED", "true")
    |> String.replace(["\"", "'"], "")
    |> String.trim()
    |> String.downcase()
    |> then(&(&1 in ~w[true 1 yes on t]))
  end

  defp lock_retry(repo, fun, opts, attempt) do
    repo.transaction(fn ->
      repo.query!("SET LOCAL lock_timeout = '#{Keyword.fetch!(opts, :lock_timeout)}'", [],
        log: false
      )

      fun.()
    end)

    :acquired
  rescue
    error in Postgrex.Error ->
      cond do
        error.postgres[:code] not in Keyword.fetch!(opts, :on) ->
          reraise error, __STACKTRACE__

        attempt < Keyword.fetch!(opts, :attempts) ->
          Process.sleep(Keyword.fetch!(opts, :backoff_seconds) * attempt * 1000)
          lock_retry(repo, fun, opts, attempt + 1)

        true ->
          :not_acquired
      end
  end

  defp statements(sql) do
    code =
      Regex.replace(
        ~r/\$(\w*)\$.*?\$\1\$|(?<![\w$])[eE]'(?:[^'\\]|\\.|'')*'|'(?:[^']|'')*'|"(?:[^"]|"")*"|--[^\n]*|\/\*.*?\*\//s,
        sql,
        " "
      )

    if String.contains?(code, ["'", "\"", "$$", "/*"]) do
      raise ArgumentError, "cannot count the statements in sql!: #{String.slice(sql, 0, 80)}"
    end

    code
    |> String.trim()
    |> String.trim_trailing(";")
    |> String.split(";")
    |> length()
  end

  defp outside_transaction!(repo, name) do
    if repo.in_transaction?(),
      do: raise(ArgumentError, "#{name} runs only in a step with transaction: false")
  end
end
