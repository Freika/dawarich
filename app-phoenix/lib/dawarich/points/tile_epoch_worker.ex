defmodule Dawarich.Points.TileEpochWorker do
  @moduledoc false
  use Oban.Worker, queue: :projections, max_attempts: 3

  def args_from_command(1, %{"user_id" => user, "timestamps" => stamps} = payload)
      when is_integer(user) and is_list(stamps) and map_size(payload) == 2 do
    if Enum.all?(stamps, &(is_nil(&1) or is_integer(&1))),
      do: {:ok, payload},
      else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  def run(repo, %{"user_id" => user, "timestamps" => timestamps}) do
    if repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL", [user], log: false).num_rows ==
         1 do
      years = timestamps |> Enum.reject(&is_nil/1) |> Enum.map(&year/1) |> Enum.uniq()
      years = if years == [], do: ["all"], else: years

      for year <- years do
        token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

        {:ok, _} =
          Dawarich.Redis.cache_command(["SET", "points:tile_epoch:#{user}:#{year}", token])
      end
    end

    :ok
  end

  defp year(stamp),
    do: stamp |> DateTime.from_unix!() |> Map.fetch!(:year) |> max(1970) |> min(2100)
end
