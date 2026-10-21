defmodule Dawarich.Immich.VerifyWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :default,
    max_attempts: 26,
    unique: [keys: [:event_id], states: :incomplete, period: :infinity]

  @keys ~w(notification_id assets immich_url pass confirmed unconfirmed)

  def args_from_command(
        1,
        %{"notification_id" => id, "assets" => assets, "immich_url" => url} = args
      )
      when is_integer(id) and is_list(assets) and is_binary(url) do
    normalized = Map.merge(%{"pass" => 1, "confirmed" => 0, "unconfirmed" => []}, args)

    if Enum.all?(Map.keys(args), &(&1 in @keys)) and
         normalized["pass"] in 1..3 and is_integer(normalized["confirmed"]) and
         normalized["confirmed"] >= 0 and is_list(normalized["unconfirmed"]) and
         Enum.all?(assets ++ normalized["unconfirmed"], &is_map/1),
       do: {:ok, normalized},
       else: {:error, "invalid_payload"}
  end

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args)

  def run(repo, oban, args, opts \\ []) do
    with {:ok, payload} <- args_from_command(1, Map.delete(args, "event_id")),
         {:ok, event} when is_binary(event) <- Ecto.UUID.cast(args["event_id"]) do
      Dawarich.Jobs.Processed.once(repo, event, "immich.verify_enrichment", fn ->
        Dawarich.Immich.Enrichment.verify(repo, oban, payload, opts)
      end)
    else
      _ -> {:error, "invalid_payload"}
    end
  end
end
