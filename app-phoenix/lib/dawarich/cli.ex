defmodule Dawarich.CLI do
  @moduledoc false

  alias Dawarich.CLI.{Jobs, Migrate, RawData, RawDataReset, RawDataStatus, Users}

  @rule String.duplicate("━", 46)

  @commands %{
    ["help"] => :help,
    ["migrate"] => {Migrate, :migrate},
    ["migrate", "status"] => {Migrate, :status},
    ["jobs", "status"] => {Jobs, :status},
    ["jobs", "drain-status"] => {Jobs, :drain_status},
    ["jobs", "resume"] => {Jobs, :resume},
    ["users", "activate"] => {Users, :activate},
    ["users", "admin"] => {Users, :admin},
    ["users", "email"] => {Users, :email},
    ["users", "password"] => {Users, :password},
    ["raw-data", "status"] => {RawDataStatus, :status},
    ["raw-data", "archive"] => {RawData, :archive},
    ["raw-data", "archive-full"] => {RawData, :archive_full},
    ["raw-data", "verify"] => {RawData, :verify},
    ["raw-data", "clear-verified"] => {RawData, :clear_verified},
    ["raw-data", "restore"] => {RawData, :restore},
    ["raw-data", "restore-all"] => {RawData, :restore_all},
    ["raw-data", "reset-all"] => {RawDataReset, :reset_all}
  }

  @own_repo [{Migrate, :migrate}]

  @rake %{
    "users:activate" => ["users", "activate"],
    "dawarich:jobs:status" => ["jobs", "status"],
    "db:migrate:status" => ["migrate", "status"],
    "points:raw_data:status" => ["raw-data", "status"],
    "points:raw_data:archive" => ["raw-data", "archive"],
    "points:raw_data:initial_archive" => ["raw-data", "archive"],
    "points:raw_data:archive_full" => ["raw-data", "archive-full"],
    "points:raw_data:verify" => ["raw-data", "verify"],
    "points:raw_data:clear_verified" => ["raw-data", "clear-verified"],
    "points:raw_data:restore" => ["raw-data", "restore"],
    "points:raw_data:restore_all" => ["raw-data", "restore-all"],
    "points:raw_data:reset_all" => ["raw-data", "reset-all"]
  }

  @sidekiq for(
             task <- ~w(release unpin rehome replay),
             into: %{},
             do:
               {"dawarich:jobs:#{task}",
                "dawarich:jobs:#{task} moves jobs between Sidekiq and Phoenix: run it with bin/rails while Sidekiq runs. It is removed together with Sidekiq."}
           )

  @places for(
            task <- ~w(dawarich:backfill_place_names dawarich:cleanup_suggested_places),
            into: %{},
            do:
              {task,
               "#{task} is not in this image yet: run bin/rails #{task} until the release that moves the Places jobs to Phoenix."}
          )

  @retired Map.merge(Map.merge(@sidekiq, @places), %{
             "points:raw_data:restore_temporary" =>
               "points:raw_data:restore_temporary was removed: it filled a cache only Rails read. Restore to the database with dawarich raw-data restore USER_ID YEAR MONTH.",
             "import:big_file" =>
               "import:big_file was removed: put the file in the watched folder (tmp/imports/watched/<user email>/) or upload it on the Imports page.",
             "imports:migrate_to_new_storage" =>
               "imports:migrate_to_new_storage was removed: run it on a Rails image (1.15.x or older) before upgrading.",
             "exports:migrate_to_new_storage" =>
               "exports:migrate_to_new_storage was removed: run it on a Rails image (1.15.x or older) before upgrading, or delete the old exports.",
             "data_cleanup:remove_duplicate_points" =>
               "data_cleanup:remove_duplicate_points was removed: it compared the latitude and longitude columns, which no longer exist.",
             "data:migrate" =>
               "data:migrate is not needed: every data migration predates Dawarich 1.0.0, the oldest database this image upgrades."
           })

  @help """
  Usage: dawarich COMMAND [ARGS]

  Maintenance commands:
    migrate                                       Bring the phoenix and oban schemas up to date
    migrate status                                Show what this image sees in the database; exit 1 if it refuses it
    jobs status                                   Job owners, outbox, Phoenix nodes and Oban job counts as JSON
    jobs drain-status                             Redacted native drain debt and rollback blockers as JSON
    jobs resume OPERATION_ID                      Resume a failed release backfill
    users activate                                Activate every user (self-hosted only)
    users admin EMAIL                             Make a user an administrator
    users email EMAIL NEW_EMAIL                   Change a user's email address
    users password EMAIL                          Set a user's password, read from standard input
    raw-data status                               Raw-data archive statistics
    raw-data archive                              Archive raw_data older than two months (does not clear it)
    raw-data verify [USER_ID YEAR MONTH]          Verify unverified archives
    raw-data clear-verified [USER_ID YEAR MONTH]  Clear the raw_data that verified archives hold
    raw-data archive-full                         Archive, verify, then clear archives verified 7 or more days ago
    raw-data restore USER_ID YEAR MONTH           Put archived raw_data back into the points of a month
    raw-data restore-all USER_ID                  Restore every archived month of a user
    raw-data reset-all                            Restore everything and delete every archive (CONFIRM=true skips the prompt)
    help                                          Show this help

  Rake task names work too, for example: dawarich "points:raw_data:restore[1,2026,1]"
  Interactive shell on the running server: dawarich remote
  """

  def main do
    log_to_stderr()
    resolved = resolve(System.argv())
    ctx = %{out: :stdio, err: :stderr, stdin: :stdio, env: System.get_env()}

    code =
      if repo?(resolved),
        do: with_repo(&dispatch(resolved, Map.put(ctx, :repo, &1))),
        else: dispatch(resolved, ctx)

    System.halt(code)
  end

  def run(argv, ctx), do: argv |> resolve() |> dispatch(ctx)

  @doc false
  def commands, do: Map.keys(@commands)

  @doc false
  def resolve([name | rest]) when is_binary(name) do
    {task, args} = rake_task(name)

    cond do
      Map.has_key?(@retired, task) -> {:retired, @retired[task]}
      Map.has_key?(@rake, task) and rest == [] -> command(@rake[task] ++ args)
      Map.has_key?(@rake, task) -> :unknown
      true -> command([name | rest])
    end
  end

  def resolve(_argv), do: :unknown

  def rule, do: @rule
  def puts(ctx, line), do: IO.puts(ctx.out, line)
  def lines(ctx, lines), do: Enum.each(lines, &puts(ctx, &1))

  def header(ctx, title, detail),
    do: lines(ctx, [@rule, "  " <> title] ++ List.wrap(detail) ++ [@rule, ""])

  def fail(ctx, message) do
    IO.puts(ctx.err, "dawarich: " <> message)
    1
  end

  defp command([a, b | args]) when is_map_key(@commands, [a, b]),
    do: {:ok, @commands[[a, b]], args}

  defp command([a | args]) when is_map_key(@commands, [a]), do: {:ok, @commands[[a]], args}
  defp command(_argv), do: :unknown

  defp rake_task(name) do
    case Regex.run(~r/\A([^\[]+)\[(.*)\]\z/s, name) do
      [_, task, ""] -> {task, []}
      [_, task, inner] -> {task, inner |> String.split(",") |> Enum.map(&String.trim/1)}
      nil -> {name, []}
    end
  end

  defp repo?({:ok, command, _args}) when is_tuple(command), do: command not in @own_repo
  defp repo?(_resolved), do: false

  defp dispatch({:ok, :help, []}, ctx) do
    IO.write(ctx.out, @help)
    0
  end

  defp dispatch({:ok, :help, _args}, ctx), do: dispatch(:unknown, ctx)

  defp dispatch({:ok, {module, fun}, args}, ctx) do
    apply(module, fun, [args, ctx])
  rescue
    error -> fail(ctx, Exception.message(error))
  catch
    kind, reason when kind in [:exit, :throw] -> fail(ctx, inspect(reason))
  end

  defp dispatch({:retired, message}, ctx), do: fail(ctx, message)

  defp dispatch(:unknown, ctx) do
    IO.write(ctx.err, @help)
    1
  end

  defp log_to_stderr do
    with {:ok, config} <- :logger.get_handler_config(:default),
         :ok <- :logger.remove_handler(:default),
         do:
           :logger.add_handler(
             :default,
             config.module,
             put_in(config, [:config, :type], :standard_error)
           )
  end

  defp with_repo(fun) do
    Application.load(:dawarich)
    {:ok, _} = Application.ensure_all_started([:ssl, :inets, :ex_aws])

    case Ecto.Migrator.with_repo(Dawarich.Repo, fun, pool_size: 2) do
      {:ok, code, _started} ->
        code

      {:error, reason} ->
        fail(%{err: :stderr}, "the database connection did not start: #{inspect(reason)}")
    end
  end
end
