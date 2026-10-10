defmodule Dawarich.Test.CapabilityCrash do
  use Phoenix.LiveView
  def render(assigns), do: ~H"<div></div>"
  def handle_event(_, _, _), do: raise("capability LiveView crash")
end

defmodule Dawarich.Test.CapabilityFailureTransport do
  def deliver(message, _env) do
    [[phrase]] =
      Dawarich.Repo.query!(
        "SELECT magic_phrase FROM shared_links WHERE magic_phrase <> '' LIMIT 1",
        [],
        log: false
      ).rows

    error = %RuntimeError{message: message.text <> phrase}

    if Application.get_env(:dawarich, :capability_failure_mode) == :raise,
      do: raise(error),
      else: {:error, error}
  end
end
