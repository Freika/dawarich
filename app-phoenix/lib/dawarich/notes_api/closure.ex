defmodule Dawarich.NotesApi.Closure do
  @moduledoc false
  alias Dawarich.{RailsTime, RubyInteger}
  alias Dawarich.NotesApi.{Payload, Read, Write}
  alias Dawarich.AccountApi.Closure, as: Account
  alias Dawarich.Imports.ImportTime

  @keys ~w(title body latitude longitude attachable_type attachable_id noted_at)

  def run(action, user, params, now) do
    zone = Account.zone(user.timezone)
    result = dispatch(action, user.id, params, zone, now)

    case result do
      {:replay, _} -> {:error, 500}
      result -> result
    end
  rescue
    _ -> {:error, 500}
  end

  defp dispatch(:index, owner, params, zone, _now), do: Read.index(owner, params, zone)

  defp dispatch(:show, owner, params, zone, _now),
    do: show(owner, RubyInteger.to_i(params["id"]), zone)

  defp dispatch(:destroy, owner, params, zone, _now),
    do: Write.destroy(owner, RubyInteger.to_i(params["id"]), zone)

  defp dispatch(action, owner, params, zone, now) do
    attrs = params["note"]

    cond do
      attrs in [nil, false, ""] or attrs == %{} ->
        {:error, 400}

      not is_map(attrs) ->
        {:error, 500}

      true ->
        attrs =
          attrs
          |> Map.take(@keys)
          |> Enum.reject(fn {_, v} -> is_list(v) or is_map(v) end)
          |> Map.new()

        attrs =
          if Map.has_key?(attrs, "noted_at"),
            do: Map.update!(attrs, "noted_at", &stamp(&1, zone, now)),
            else: attrs

        attrs =
          Map.new(attrs, fn {key, value} ->
            {key, if(is_boolean(value), do: to_string(value), else: value)}
          end)

        if action == :create do
          Write.create(owner, if(attrs == %{}, do: %{"body" => nil}, else: attrs), zone, now)
        else
          id = RubyInteger.to_i(params["id"])

          with {:ok, _} <- show(owner, id, zone) do
            if attrs == %{},
              do: show(owner, id, zone),
              else: Write.update(owner, id, attrs, zone, now)
          end
        end
    end
  end

  defp show(owner, id, zone) do
    RailsTime.with_zone(zone, fn ->
      case Payload.rows("n.user_id = $1 AND n.id = $2", [owner, id]) do
        [row] -> {:ok, Payload.term(row)}
        [] -> :not_found
      end
    end)
  end

  defp stamp(nil, _zone, _now), do: nil

  defp stamp(value, zone, now) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _} ->
        DateTime.to_iso8601(time)

      _ ->
        case ImportTime.parse(value, zone, now) do
          nil -> nil
          seconds -> seconds |> DateTime.from_unix!() |> DateTime.to_iso8601()
        end
    end
  rescue
    _ -> nil
  end

  defp stamp(_, _zone, _now), do: nil
end
