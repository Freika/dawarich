defmodule Dawarich.TripStream do
  @moduledoc false

  def stream_name(id, secret \\ Dawarich.RailsSecret.fetch()) when is_integer(id) do
    global_id = Base.url_encode64("gid://dawarich/Trip/#{id}", padding: false)
    Dawarich.RailsMessages.stream_name([global_id], secret)
  end
end
