defmodule Dawarich.RouteVideos do
  @moduledoc false

  defdelegate create(repo, user, params, now, locale, policy), to: Dawarich.RouteVideos.Writes
  defdelegate destroy(repo, user_id, id, now), to: Dawarich.RouteVideos.Writes
  defdelegate reserve_upload(scope, attrs, opts), to: Dawarich.RouteVideos.Scoped
  defdelegate create_video(scope, attrs, opts), to: Dawarich.RouteVideos.Scoped
  defdelegate discard_upload(scope, signed_id, opts), to: Dawarich.RouteVideos.Scoped
  defdelegate destroy_video(scope, id, opts), to: Dawarich.RouteVideos.Scoped
  defdelegate gallery(scope, opts), to: Dawarich.RouteVideos.Scoped
  defdelegate zone(repo, settings), to: Dawarich.RouteVideos.Scoped
end
