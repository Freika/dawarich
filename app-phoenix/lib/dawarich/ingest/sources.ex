defmodule Dawarich.Ingest.Sources do
  @moduledoc false

  alias Dawarich.Ingest.{Cast, Ruby}

  @scalars ~w(tracker_id topic ssid bssid)a
  @enums ~w(connection trigger battery_status)a
  @recheck_ms 60_000
  @array "(SELECT CASE WHEN j IS NULL THEN NULL ELSE ARRAY(SELECT jsonb_array_elements_text(j)) END FROM (SELECT $%::jsonb AS j) t)::text[]"
  @digest ~s[md5(jsonb_build_object('tracker_id', v."tracker_id", 'topic', v."topic", 'ssid', v."ssid", 'bssid', v."bssid", 'connection', v."connection", 'trigger', v."trigger", 'battery_status', v."battery_status", 'inrids', v."inrids", 'in_regions', v."in_regions")::text)]
  @columns ~s["tracker_id", "topic", "ssid", "bssid", "connection", "trigger", "battery_status", "inrids", "in_regions"]
  @sql """
  WITH v AS (SELECT $1::varchar AS "tracker_id", $2::varchar AS "topic", $3::varchar AS "ssid", $4::varchar AS "bssid",
    $5::integer AS "connection", $6::integer AS "trigger", $7::integer AS "battery_status",
    #{String.replace(@array, "%", "8")} AS "inrids", #{String.replace(@array, "%", "9")} AS "in_regions"),
  d AS (SELECT v.*, #{@digest} AS digest FROM v),
  ins AS (INSERT INTO point_sources (digest, #{@columns}, created_at, updated_at)
    SELECT d.digest, #{@columns}, NOW(), NOW() FROM d
    WHERE NOT EXISTS (SELECT 1 FROM point_sources ps WHERE ps.digest = d.digest)
    ON CONFLICT (digest) DO NOTHING RETURNING id)
  SELECT id FROM ins UNION ALL SELECT ps.id FROM point_sources ps, d WHERE ps.digest = d.digest LIMIT 1
  """

  def combo(payload) do
    Enum.map(@scalars, &bind(payload[&1])) ++
      Enum.map(@enums, &(payload[&1] && Cast.enum(&1, payload[&1]))) ++
      Enum.map([:inrids, :in_regions], &array(payload, &1))
  end

  def resolve(repo, combo) do
    Enum.find_value(1..2, fn _ ->
      case repo.query!(@sql, combo, log: false).rows do
        [[id]] -> id
        [] -> nil
      end
    end)
  end

  def available?(repo, now \\ System.monotonic_time(:millisecond)) do
    config = if function_exported?(repo, :config, 0), do: repo.config(), else: []
    key = {repo, Keyword.take(config, [:database, :prefix])}

    case Map.get(cache(), key, :unknown) do
      true -> true
      {:absent, at} when now - at < @recheck_ms -> false
      _ -> remember(key, column?(repo), now)
    end
  end

  def forget, do: :persistent_term.erase(__MODULE__)

  defp cache, do: :persistent_term.get(__MODULE__, %{})

  defp remember(key, value, now) do
    stored = if value, do: true, else: {:absent, now}
    :persistent_term.put(__MODULE__, Map.put(cache(), key, stored))
    value
  end

  defp column?(repo) do
    repo.query!(
      "SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'points' AND column_name = 'source_id'",
      [],
      log: false
    ).rows != []
  end

  defp bind(nil), do: nil
  defp bind(value) when is_binary(value), do: value
  defp bind(value) when is_integer(value), do: Integer.to_string(value)
  defp bind(_value), do: Ruby.unsupported!("float or boolean device field")

  defp array(payload, key) do
    case Map.fetch(payload, key) do
      :error -> []
      {:ok, nil} -> nil
      {:ok, list} when is_list(list) -> Enum.map(list, &element/1)
      {:ok, _} -> Ruby.unsupported!("non-array device regions")
    end
  end

  defp element(nil), do: nil
  defp element(value) when is_binary(value), do: value
  defp element(_value), do: Ruby.unsupported!("non-string array element")
end
