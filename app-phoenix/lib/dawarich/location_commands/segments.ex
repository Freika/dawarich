defmodule Dawarich.LocationCommands.Segments do
  @moduledoc false
  alias Dawarich.{Maps, Repo, RubyInteger, TrackSegmentPage}
  alias Dawarich.Tracks.SegmentEditor

  def list(scope, track_id) do
    Maps.with_actor(scope, fn actor ->
      case TrackSegmentPage.load(actor, RubyInteger.to_i(track_id)) do
        {:ok, page} -> {:ok, Map.put(page, :modes, Dawarich.Tracks.Settings.enabled_modes(actor))}
        :rails -> {:error, :not_found}
      end
    end)
  end

  def override(scope, track_id, id, mode, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo
      |> SegmentEditor.apply_override(actor, int(track_id), int(id), mode, ctx(opts))
      |> typed()
    end)
  end

  def reset(scope, track_id, id, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      Repo |> SegmentEditor.reset_to_auto(actor, int(track_id), int(id), ctx(opts)) |> typed()
    end)
  end

  defp ctx(opts), do: %{now: Keyword.get(opts, :now, DateTime.utc_now())}
  defp int(value), do: RubyInteger.to_i(value)

  defp typed({:ok, result}), do: {:ok, result}
  defp typed({:error, %{error_code: code}}), do: {:error, code}
  defp typed(:not_found), do: {:error, :not_found}
  defp typed(_), do: {:error, :unavailable}
end
