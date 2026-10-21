defmodule Dawarich.Places.NameFetchWorker do
  @moduledoc false
  use Oban.Worker, queue: :reverse_geocoding, max_attempts: 26
  alias Dawarich.Geocoding.Config
  alias Dawarich.Jobs.Processed
  alias Dawarich.Places.NameFetcher

  def args_from_command(1, %{"user_id" => user, "place_id" => place} = p)
      when map_size(p) == 2 and is_integer(user) and is_integer(place) and
             user in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and
             place in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
      do: {:ok, p}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(repo, args, opts \\ []) do
    if Processed.done?(repo, args["event_id"]) do
      :ok
    else
      config = Keyword.get_lazy(opts, :config, fn -> Config.resolve(repo) end)
      data = NameFetcher.lookup(repo, args["user_id"], args["place_id"], config)

      if data == :missing do
        {:error, :not_found}
      else
        {:ok, :ok} =
          repo.transaction(fn ->
            if Processed.claim!(repo, args["event_id"], "places.name_fetch") do
              case data do
                {:ok, result} ->
                  NameFetcher.apply(repo, args["user_id"], args["place_id"], result, config)

                _ ->
                  :ok
              end
            end

            :ok
          end)

        :ok
      end
    end
  end
end
