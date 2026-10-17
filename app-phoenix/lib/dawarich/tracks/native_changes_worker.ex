defmodule Dawarich.Tracks.NativeChangesWorker do
  @moduledoc false
  use Oban.Worker, queue: :tracks, max_attempts: 20

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: payload}) do
    intent =
      :crypto.hash(:sha256, "tracks:legacy-notification:#{id}")
      |> binary_part(0, 16)
      |> Ecto.UUID.load!()

    Dawarich.AfterCommit.Worker.run(Dawarich.Jobs.repo(), %{
      "operation" => "tracks",
      "payload" => payload,
      "intent_id" => intent
    })
  end
end
