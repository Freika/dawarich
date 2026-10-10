defmodule Dawarich.Stats.PageRefreshWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3
  alias Dawarich.{Repo, State}
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.Stats.PageRefresh
  alias Dawarich.Digests.{Context, CalculateMonth, CalculateYear, Store}
  alias Dawarich.Jobs.Processed

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(args)

  def run(args, opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)

    with {:ok, scope, period, resource} <- admitted(args, opts),
         true <- PageRefresh.revision(repo, scope, resource, period) == args["revision"] do
      if Processed.done?(repo, args["receipt"]) do
        :ok
      else
        calculate = Keyword.get(opts, :calculate, &calculate/3)
        output = calculate.(repo, args, opts)
        if fun = opts[:before_persist], do: fun.()
        persist(repo, scope, period, resource, args, output, opts)
      end
    else
      _ -> {:cancel, :unauthorized}
    end
  rescue
    _ ->
      repo = Keyword.get(opts, :repo, Repo)
      State.put_cursor(repo, PageRefresh.key(args), "failed")
      {:error, :calculation_failed}
  end

  defp admitted(
         %{"version" => 1, "user_id" => id, "resource" => raw, "identity" => identity} = args,
         opts
       )
       when raw in ["insights", "counts"] and is_integer(id) do
    with {:ok, proof} <- Base.decode16(identity),
         {:ok, scope} <-
           DataAccess.admit(%Dependencies{actor_id: id, locale: "en", identity: proof},
             settings: true,
             full_access: raw == "insights",
             self_hosted:
               Keyword.get(
                 opts,
                 :self_hosted,
                 Dawarich.ReleaseMigration.self_hosted?(System.get_env())
               )
           ),
         {:ok, scope, period} <-
           Dawarich.Analytics.Period.admit(
             scope,
             Map.new(
               for key <- ~w(year month), not is_nil(args[key]), do: {key, to_string(args[key])}
             ),
             :insights,
             opts
           ),
         true <- period.zone == args["zone"] and period.unit == args["unit"] do
      {:ok, scope, period, if(raw == "insights", do: :insights, else: :counts)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp admitted(_, _), do: {:error, :unauthorized}

  defp calculate(repo, %{"resource" => "insights"} = args, opts) do
    context = Context.load!(repo, args["user_id"], opts)
    yearly = CalculateYear.attributes(repo, context, args["year"])

    monthly =
      if args["month"] in 1..12,
        do: CalculateMonth.attributes(repo, context, args["year"], args["month"])

    {:digests, context, yearly, monthly}
  end

  defp calculate(repo, %{"resource" => "counts", "user_id" => id}, _opts) do
    [[geocoded, without]] =
      repo.query!(
        "SELECT count(*) FILTER (WHERE reverse_geocoded_at IS NOT NULL),count(*) FILTER (WHERE reverse_geocoded_at IS NOT NULL AND city IS NULL AND country_name IS NULL AND country IS NULL AND country_id IS NULL) FROM points WHERE user_id=$1",
        [id],
        log: false
      ).rows

    {:counts, geocoded, without, Dawarich.AfterCommit.Visibility.generation(repo, id)}
  end

  defp persist(repo, scope, _period, resource, args, output, opts) do
    case Dawarich.Transaction.run(repo, fn ->
           repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [scope.user.id], log: false)

           with {:ok, fresh, current, ^resource} <- admitted(args, opts),
                true <- PageRefresh.revision(repo, fresh, resource, current) == args["revision"] do
             if Processed.claim!(repo, args["receipt"], "native-page-refresh") do
               store(repo, args, output, opts)
               if fun = opts[:before_ready], do: fun.()
               State.put_cursor(repo, PageRefresh.key(args), "ready")

               State.put_cursor(
                 repo,
                 PageRefresh.published_key(scope.user.id, resource, current),
                 args["revision"]
               )
             end

             :ok
           else
             _ -> repo.rollback(:stale)
           end
         end) do
      {:ok, :ok} ->
        Phoenix.PubSub.broadcast(
          Dawarich.PubSub,
          PageRefresh.topic(scope.user.id),
          {:analytics_ready, args["receipt"], args["revision"]}
        )

        :ok

      {:error, :stale} ->
        {:cancel, :stale}

      {:error, _} ->
        {:error, :calculation_failed}
    end
  end

  defp store(repo, args, {:digests, context, yearly, monthly}, opts) do
    if yearly, do: Store.save!(repo, context, "yearly", args["year"], nil, yearly, opts)

    if monthly,
      do: Store.save!(repo, context, "monthly", args["year"], args["month"], monthly, opts)
  end

  defp store(repo, args, {:counts, geocoded, without, generation}, opts) do
    repo.query!(
      "INSERT INTO phoenix.stats_point_counts (user_id,geocoded,without_data,computed_at) VALUES ($1,$2,$3,$4) ON CONFLICT (user_id) DO UPDATE SET geocoded=EXCLUDED.geocoded,without_data=EXCLUDED.without_data,computed_at=EXCLUDED.computed_at",
      [args["user_id"], geocoded, without, Keyword.get(opts, :now, DateTime.utc_now())],
      log: false
    )

    State.put_cursor(repo, "stats_point_counts:#{args["user_id"]}", generation)
  end
end
