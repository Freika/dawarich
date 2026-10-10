defmodule Dawarich.UserData.Restore.V1 do
  @moduledoc false
  alias Dawarich.UserData.{Versions, Restore}
  alias Dawarich.UserData.Restore.{V2, Messages, Places, Visits, Points}
  alias Dawarich.Ingest.Ruby
  @modules %{"places" => Places, "visits" => Visits, "points" => Points}

  def call(repo, user, dir, context) do
    acc = %{
      stats: Restore.initial_stats(),
      expected: nil,
      buffers: Map.new(~w(places visits points), &{&1, []})
    }

    acc =
      Versions.reduce_v1(Path.join(dir, "data.json"), context, acc, fn event, acc ->
        case event do
          {:section, "counts", data} ->
            %{acc | expected: if(is_map(data), do: data, else: nil)}

          {:section, "settings", data} ->
            acc = flush(acc, "places", repo, user, context)

            if Ruby.present?(data),
              do: %{
                acc
                | stats: V2.section(repo, user, dir, "settings", data, acc.stats, context)
              },
              else: acc

          {:section, name, data} ->
            acc = flush(acc, "places", repo, user, context)
            %{acc | stats: V2.section(repo, user, dir, name, data, acc.stats, context)}

          {:row, name, row} ->
            acc =
              if name in ~w(visits points),
                do: flush(acc, "places", repo, user, context),
                else: acc

            acc = if name == "points", do: flush(acc, "visits", repo, user, context), else: acc
            acc = put_in(acc, [:buffers, name], [row | acc.buffers[name]])

            if length(acc.buffers[name]) >= 5000,
              do: flush(acc, name, repo, user, context),
              else: acc
        end
      end)

    acc = Enum.reduce(~w(places visits points), acc, &flush(&2, &1, repo, user, context))
    Messages.completeness(acc.stats, acc.expected)
    acc.stats
  end

  defp flush(acc, name, repo, user, context) do
    case acc.buffers[name] do
      [] ->
        acc

      buffer ->
        count = @modules[name].call(repo, user, Enum.reverse(buffer), context)
        %{acc | stats: V2.add(acc.stats, name, count), buffers: Map.put(acc.buffers, name, [])}
    end
  end
end
