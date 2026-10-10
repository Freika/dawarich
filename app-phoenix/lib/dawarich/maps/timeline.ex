defmodule Dawarich.Maps.Timeline do
  @moduledoc false
  alias Dawarich.{Entitlements, MapWindow, Maps, RubyInteger}
  alias Dawarich.Maps.Dependencies.Timeline, as: Source
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @bounds ~w(start_at end_at)

  def feed(scope, params, opts \\ []) when is_map(params) do
    if Enum.all?(@bounds, &(is_nil(params[&1]) or is_binary(params[&1]))) do
      Maps.with_actor(scope, fn actor ->
        now = now(opts)
        window = MapWindow.build(bounds(params, now), Dawarich.UserSettings.get(actor), now, nil)
        feed = Source.feed(actor, window, cutoff(actor, opts))

        {:ok,
         %{
           days: feed.days,
           redetected: feed.redetected,
           requested_date: window.start_date,
           restricted: restricted?(actor, opts),
           unit: Source.unit(actor)
         }}
      end)
    else
      {:error, :invalid}
    end
  end

  def track(scope, id) do
    Maps.with_actor(scope, fn actor ->
      case Source.track(actor, RubyInteger.to_i(id)) do
        nil -> {:error, :not_found}
        track -> {:ok, track}
      end
    end)
  end

  defp bounds(params, now) do
    Map.new(@bounds, fn key ->
      value = params[key]
      {key, if(Ruby.blank?(value), do: Integer.to_string(DateTime.to_unix(now)), else: value)}
    end)
  end

  defp cutoff(actor, opts), do: if(restricted?(actor, opts), do: now(opts))

  defp restricted?(actor, opts) do
    hosted = Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
    not Entitlements.full_access?(actor, hosted, now(opts))
  end

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
end
