defmodule Dawarich.DemoData.Importer do
  @moduledoc false
  alias Dawarich.DemoData.{Points, Tracks}

  def call(repo, user, opts \\ []) do
    result =
      Dawarich.Transaction.run(
        repo,
        fn ->
          repo.query!(
            "SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
            [user.id],
            log: false
          )

          if repo.query!(
               "SELECT id FROM imports WHERE user_id=$1 AND demo=true LIMIT 1",
               [user.id],
               log: false
             ).rows != [] do
            :exists
          else
            anchor = anchor(repo, user, Keyword.get(opts, :now, DateTime.utc_now()))

            [[id]] =
              repo.query!(
                "INSERT INTO imports (user_id,name,source,status,demo,processing_started_at,created_at,updated_at) VALUES ($1,'Demo Data (Berlin + Prague)',6,2,true,now(),now(),now()) RETURNING id",
                [user.id],
                log: false
              ).rows

            Points.seed(
              repo,
              user.id,
              id,
              anchor,
              Keyword.get_lazy(opts, :points, fn -> fixture("demo_data") end)
            )

            Tracks.seed(
              repo,
              user.id,
              id,
              anchor,
              Keyword.get_lazy(opts, :derivatives, fn -> fixture("demo_derivatives") end)[
                "tracks"
              ]
            )

            Dawarich.DemoData.Derivatives.seed(
              repo,
              user,
              anchor,
              Keyword.get_lazy(opts, :derivatives, fn -> fixture("demo_derivatives") end)
            )

            invalidate(repo, user)
            :created
          end
        end
      )

    case result do
      {:ok, :created} ->
        :created

      {:ok, status} ->
        status

      {:error, _} ->
        :error
    end
  rescue
    _ -> :error
  end

  def invalidate(repo, user, months \\ nil) do
    months =
      months ||
        repo.query!(
          "SELECT DISTINCT extract(year FROM to_timestamp(timestamp) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(timestamp) AT TIME ZONE $2)::int FROM points WHERE user_id=$1 AND import_id IN (SELECT id FROM imports WHERE user_id=$1 AND demo=true)",
          [user.id, zone(user)],
          log: false
        ).rows

    setting = Dawarich.UserSettings.get(user)["timezone"] || "UTC"
    setting = if setting == "", do: "UTC", else: setting

    keys =
      for [year, month] <- months, segment <- ~w(lite pro) do
        label = "#{year}-" <> String.pad_leading(Integer.to_string(month), 2, "0")
        "timeline_month_summary/#{user.id}/#{label}/#{setting}/#{segment}/v3"
      end

    keys =
      keys
      |> Enum.flat_map(fn key ->
        month = Dawarich.Visits.CacheGeneration.physical_key(key, repo)

        [
          key,
          month,
          Dawarich.AfterCommit.Visibility.key(repo, key),
          Dawarich.AfterCommit.Visibility.key(repo, month)
        ]
      end)
      |> Enum.uniq()

    Dawarich.AfterCommit.cache(repo, "keys", %{"user_id" => user.id, "keys" => keys})

    Dawarich.Stats.CacheInvalidation.call(repo, %{
      "user_id" => user.id,
      "year" => nil,
      "scope" => "all"
    })
  end

  def fixture(name),
    do:
      :dawarich
      |> :code.priv_dir()
      |> Path.join(name <> ".json.gz")
      |> File.read!()
      |> :zlib.gunzip()
      |> Jason.decode!()

  def zone(user) do
    value = Dawarich.UserSettings.get(user)["timezone"]
    Dawarich.TimeZoneName.to_iana(if is_binary(value) and value != "", do: value, else: "UTC")
  end

  def anchor(repo, user, now) do
    [[stamp]] =
      repo.query!(
        "SELECT extract(epoch FROM (date_trunc('day', $1::timestamptz AT TIME ZONE $2) AT TIME ZONE $2))::bigint",
        [now, zone(user)],
        log: false
      ).rows

    stamp
  end
end
