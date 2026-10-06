defmodule Dawarich.DemoData.Importer do
  @moduledoc false
  alias Dawarich.DemoData.{Points, Tracks}

  def call(repo, user, opts \\ []) do
    result =
      repo.transaction(
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

            :created
          end
        end,
        mode: :savepoint
      )

    case result do
      {:ok, status} -> status
      {:error, _} -> :error
    end
  rescue
    _ -> :error
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
    value = user.settings["timezone"]
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
