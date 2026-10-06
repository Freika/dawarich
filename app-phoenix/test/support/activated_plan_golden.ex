defmodule Dawarich.Test.ActivatedPlanGolden do
  @moduledoc false

  def activate(kase) do
    request = kase["request"]
    path = request["target"] |> String.split("?") |> hd()
    slices = get_in(kase, ["env", "DAWARICH_RAILS_SLICES"])

    deferred = path in ~w(/api/v1/health /api/v1/ready /health /ready)

    if kase["expect"] == "rails" and slices in [nil, ""] and not deferred,
      do: kase |> Map.put("expect", "own") |> cloud_headers(),
      else: kase
  end

  defp cloud_headers(kase) do
    if get_in(kase, ["env", "SELF_HOSTED"]) == "false",
      do:
        Map.put(
          kase,
          "ignore",
          (kase["ignore"] || []) ++ ~w(x-ratelimit-limit x-ratelimit-remaining x-ratelimit-reset)
        ),
      else: kase
  end
end
