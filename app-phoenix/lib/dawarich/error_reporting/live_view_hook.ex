defmodule Dawarich.ErrorReporting.LiveViewHook do
  def on_mount(:default, _params, _session, socket) do
    Sentry.Context.set_tags_context(%{"surface" => "live_view"})
    {:cont, socket}
  end
end
