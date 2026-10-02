defmodule Dawarich.MapApi.Cache do
  @moduledoc false

  def points_etag(user_id, params, meta) do
    key =
      Enum.map_join(
        [
          "points/index",
          user_id,
          meta.from,
          meta.to,
          params["order"] || "desc",
          params["slim"] == "true",
          params["page"],
          params["per_page"] || 100,
          params["import_id"],
          params["anomalies_only"],
          params["include_anomalies"],
          params["min_longitude"],
          params["max_longitude"],
          params["min_latitude"],
          params["max_latitude"],
          meta.max_timestamp,
          meta.count
          | time_parts(meta.max_updated)
        ],
        "/",
        &if(is_nil(&1), do: "", else: to_string(&1))
      )

    prefix = System.get_env("RAILS_CACHE_ID") || System.get_env("RAILS_APP_VERSION")
    key = if prefix, do: prefix <> "/" <> key, else: key
    ~s(W/"#{:crypto.hash(:sha256, key) |> Base.encode16(case: :lower) |> binary_part(0, 32)}")
  end

  def fresh?(none_match, etag, modified, since) do
    case none_match do
      [] ->
        modified != nil and since != nil and NaiveDateTime.compare(since, modified) != :lt

      values ->
        values
        |> Enum.flat_map(&String.split(&1, ","))
        |> Enum.map(&String.trim/1)
        |> Enum.any?(&(&1 in [etag, "*"]))
    end
  end

  defp time_parts(nil), do: [nil]

  defp time_parts(%NaiveDateTime{} = at) do
    date = NaiveDateTime.to_date(at)

    [
      at.second,
      at.minute,
      at.hour,
      at.day,
      at.month,
      at.year,
      rem(Date.day_of_week(date), 7),
      Date.day_of_year(date),
      false,
      "UTC"
    ]
  end
end
