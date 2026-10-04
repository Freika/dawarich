defmodule Dawarich.RouteVideos do
  @moduledoc false

  defdelegate create(repo, user, params, now, locale, policy), to: Dawarich.RouteVideos.Writes
  defdelegate destroy(repo, user_id, id, now), to: Dawarich.RouteVideos.Writes
end
