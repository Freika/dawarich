defmodule Dawarich.RouteVideos.AttachmentJob do
  @moduledoc false
  alias Dawarich.{RailsCommands, Standalone}
  alias Dawarich.Jobs.Ownership

  def enqueue!(repo, payload) do
    owner = Ownership.lock(repo, "cron:route_videos_purge_job")

    if Standalone.enabled?() or owner == :oban do
      Dawarich.RouteVideos.AttachmentEffects.enqueue!(repo, payload)
    else
      RailsCommands.insert!(repo, "route_videos.attachment_job", payload)
    end
  end
end
