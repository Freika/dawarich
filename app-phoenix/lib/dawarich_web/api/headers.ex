defmodule DawarichWeb.Api.Headers do
  @moduledoc false

  def dawarich(authenticated?, version) do
    [
      {"x-dawarich-response",
       if(authenticated?, do: "Hey, I'm alive and authenticated!", else: "Hey, I'm alive!")},
      {"x-dawarich-version", version}
    ]
  end

  def rate_limit(%{self_hosted: true}), do: []
  def rate_limit(%{authenticated: false}), do: []
  def rate_limit(%{throttle: nil}), do: []

  def rate_limit(%{throttle: %{limit: limit, count: count, period: period}, now: now}) do
    [
      {"x-ratelimit-limit", Integer.to_string(limit)},
      {"x-ratelimit-remaining", Integer.to_string(max(limit - count, 0))},
      {"x-ratelimit-reset", Integer.to_string(now + (period - rem(now, period)))}
    ]
  end
end
