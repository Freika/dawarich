defmodule Dawarich.Onboarding do
  @moduledoc false
  alias Dawarich.{Maps, Repo}
  alias Dawarich.DemoData.{Destroyer, Importer}

  def complete(scope) do
    Maps.with_actor(scope, fn actor ->
      case Dawarich.Settings.Onboarding.complete(Repo, actor.id) do
        {:ok, :ok} -> :ok
        _ -> {:error, :save_failed}
      end
    end)
  end

  def load_demo(scope, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      case Importer.call(Repo, actor, opts) do
        result when result in [:created, :exists] ->
          {:ok, %{result: result, landing: landing(actor, opts)}}

        :error ->
          {:error, :failed}
      end
    end)
  end

  def remove_demo(scope) do
    Maps.with_actor(scope, fn actor ->
      case Destroyer.call(Repo, actor) do
        result when result in [:destroyed, :no_demo_data] -> {:ok, result}
        :error -> {:error, :failed}
      end
    end)
  end

  def qr_svg(scope, base_url) when is_binary(base_url) do
    Maps.with_actor(scope, fn actor ->
      {:ok, Dawarich.QrSvg.api_key(base_url <> "/", actor.api_key, 3)}
    end)
  end

  def landing(user, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    zone = Importer.zone(user)

    [[date]] =
      Repo.query!("SELECT ($1::timestamptz AT TIME ZONE $2)::date - 1", [now, zone], log: false).rows

    {first, last} = Dawarich.Visits.Calendar.previous_day(Repo, zone, DateTime.to_unix(now))
    first = String.replace(first, "+00:00", "Z")
    last = last |> String.replace(~r/\.\d+/, "") |> String.replace("+00:00", "Z")

    "/map/v2?" <>
      URI.encode_query(%{
        "panel" => "timeline",
        "date" => Date.to_iso8601(date),
        "start_at" => first,
        "end_at" => last
      })
  end
end
