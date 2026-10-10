defmodule Dawarich.Test.CapabilityCrash do
  use Phoenix.LiveView
  def render(assigns), do: ~H"<div></div>"
  def handle_event(_, _, _), do: raise("capability LiveView crash")
end

defmodule Dawarich.Test.CapabilityJob do
  use Oban.Worker, queue: :mailers

  def perform(%Oban.Job{args: args}) do
    require Logger
    Logger.debug(%{invitation_job: args})
    {:error, %RuntimeError{message: args["token"]}}
  end
end
