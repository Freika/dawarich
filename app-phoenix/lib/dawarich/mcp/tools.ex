defmodule Dawarich.Mcp.Tools do
  @moduledoc false
  alias Dawarich.Mcp.{LatestLocation, SearchVisits, Timeline}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @tools Jason.decode!(
           ~S|[{"name":"get_timeline","title":"Get timeline","description":"Return the authenticated user's visits and journeys for a bounded time range. A journey that crosses midnight is listed in full on its start date and again, for the part after midnight, on later dates with continuation_of_date set. When adding up journeys across days, skip a continuation row whose continuation_of_date is also in the result, or use each day's summary. Visit status 'confirmed' means the user confirmed the visit; 'suggested' means Dawarich detected it automatically and it is not confirmed yet.","inputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"start_at":{"type":"string","description":"Range start as an ISO 8601 date or timestamp."},"end_at":{"type":"string","description":"Inclusive range end as an ISO 8601 date or timestamp."},"distance_unit":{"type":"string","enum":["km","mi"],"description":"Distance unit; defaults to the user setting."}},"required":["start_at","end_at"],"additionalProperties":false,"type":"object"},"outputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"days":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"date":{"type":"string","format":"date"},"summary":{"type":"object","additionalProperties":false,"properties":{"total_distance":{"type":"number"},"distance_unit":{"type":"string","enum":["km","mi"]},"places_visited":{"type":"integer"},"time_moving_minutes":{"type":"integer"},"time_stationary_minutes":{"type":"integer"}},"required":["total_distance","distance_unit","places_visited","time_moving_minutes","time_stationary_minutes"]},"entries":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"type":{"type":"string","enum":["visit","journey"]},"name":{"type":["string","null"]},"status":{"type":"string"},"started_at":{"type":"string","format":"date-time"},"ended_at":{"type":"string","format":"date-time"},"duration_minutes":{"type":"number"},"continuation_of_date":{"type":["string","null"],"format":"date","description":"Start date of a journey listed in full on that date; this row is its part after midnight."},"place":{"$ref":"#/$defs/location"},"area":{"$ref":"#/$defs/area"},"distance":{"type":"number"},"distance_unit":{"type":"string","enum":["km","mi"]},"dominant_mode":{"type":["string","null"]},"average_speed":{"type":"number"},"speed_unit":{"type":"string"}},"required":["type","started_at","ended_at","duration_minutes"]}}},"required":["date","summary","entries"]}}},"required":["days"],"$defs":{"location":{"type":["object","null"],"additionalProperties":false,"properties":{"name":{"type":["string","null"]},"latitude":{"type":"number"},"longitude":{"type":"number"},"city":{"type":["string","null"]},"country":{"type":["string","null"]}},"required":["name","latitude","longitude","city","country"]},"area":{"type":["object","null"],"additionalProperties":false,"properties":{"name":{"type":"string"},"latitude":{"type":"number"},"longitude":{"type":"number"},"radius":{"type":"number"}},"required":["name","latitude","longitude","radius"]}}},"annotations":{"destructiveHint":false,"idempotentHint":true,"openWorldHint":false,"readOnlyHint":true}},{"name":"get_latest_location","title":"Get latest location","description":"Return the authenticated user's newest visible non-anomalous location point.","inputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{},"additionalProperties":false,"type":"object"},"outputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"point":{"type":["object","null"],"properties":{"id":{"type":"integer"},"latitude":{"type":"number"},"longitude":{"type":"number"},"recorded_at":{"type":"string","format":"date-time"},"country_name":{"type":"string"},"velocity":{"type":["number","null"]},"tracker_id":{"type":["string","null"]}}}},"required":["point"],"type":"object"},"annotations":{"destructiveHint":false,"idempotentHint":true,"openWorldHint":false,"readOnlyHint":true}},{"name":"search_visits","title":"Search visits","description":"Find the authenticated user's visits whose name, place, city, country or area matches a text query, newest first, with the total number of matches. Visit status 'confirmed' means the user confirmed the visit; 'suggested' means Dawarich detected it automatically and it is not confirmed yet.","inputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"query":{"type":"string","minLength":2,"description":"Case-insensitive text matched against visit, place, city, country and area names."},"limit":{"type":"integer","minimum":1,"maximum":50,"description":"Maximum number of visits to return; defaults to 20."}},"required":["query"],"additionalProperties":false,"type":"object"},"outputSchema":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","additionalProperties":false,"properties":{"total_count":{"type":"integer"},"visits":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"type":{"type":"string","enum":["visit","journey"]},"name":{"type":["string","null"]},"status":{"type":"string"},"started_at":{"type":"string","format":"date-time"},"ended_at":{"type":"string","format":"date-time"},"duration_minutes":{"type":"number"},"continuation_of_date":{"type":["string","null"],"format":"date","description":"Start date of a journey listed in full on that date; this row is its part after midnight."},"place":{"$ref":"#/$defs/location"},"area":{"$ref":"#/$defs/area"},"distance":{"type":"number"},"distance_unit":{"type":"string","enum":["km","mi"]},"dominant_mode":{"type":["string","null"]},"average_speed":{"type":"number"},"speed_unit":{"type":"string"}},"required":["type","started_at","ended_at","duration_minutes"]}}},"required":["total_count","visits"],"$defs":{"location":{"type":["object","null"],"additionalProperties":false,"properties":{"name":{"type":["string","null"]},"latitude":{"type":"number"},"longitude":{"type":"number"},"city":{"type":["string","null"]},"country":{"type":["string","null"]}},"required":["name","latitude","longitude","city","country"]},"area":{"type":["object","null"],"additionalProperties":false,"properties":{"name":{"type":"string"},"latitude":{"type":"number"},"longitude":{"type":"number"},"radius":{"type":"number"}},"required":["name","latitude","longitude","radius"]}}},"annotations":{"destructiveHint":false,"idempotentHint":true,"openWorldHint":false,"readOnlyHint":true}}]|
         )
  def list, do: @tools

  def call(user, %{"name" => name} = params) do
    args = params["arguments"] || %{}

    case Enum.find(@tools, &(&1["name"] == name)) do
      nil ->
        {:rpc_error, -32602, "Unknown tool: #{name}"}

      tool ->
        if valid?(args, tool["inputSchema"]) do
          case run(name, user, args) do
            {:ok, payload} ->
              text = payload |> Ruby.json() |> IO.iodata_to_binary()

              {:ok,
               %{
                 "content" => [%{"type" => "text", "text" => text}],
                 "isError" => false,
                 "structuredContent" => Jason.decode!(text)
               }}

            {:error, message} ->
              failure(message)
          end
        else
          failure("Invalid arguments")
        end
    end
  rescue
    _ -> {:rpc_error, -32603, "Internal error"}
  end

  def call(_, _), do: {:rpc_error, -32602, "Invalid params"}
  defp run("get_latest_location", user, _), do: LatestLocation.fetch(user)
  defp run("get_timeline", user, args), do: Timeline.fetch(user, args)
  defp run("search_visits", user, args), do: SearchVisits.fetch(user, args)

  defp failure(message),
    do: {:ok, %{"content" => [%{"type" => "text", "text" => message}], "isError" => true}}

  defp valid?(args, schema) when is_map(args) do
    properties = schema["properties"] || %{}

    Enum.all?(schema["required"] || [], &Map.has_key?(args, &1)) and
      Enum.all?(args, fn {key, value} ->
        case properties[key] do
          nil ->
            false

          %{"type" => "string"} = rule ->
            is_binary(value) and String.length(value) >= (rule["minLength"] || 0) and
              (is_nil(rule["enum"]) or value in rule["enum"])

          %{"type" => "integer"} = rule ->
            is_integer(value) and value >= rule["minimum"] and value <= rule["maximum"]

          _ ->
            false
        end
      end)
  end

  defp valid?(_, _), do: false
end
