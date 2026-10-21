defmodule Dawarich.Auth.Recovery.Notification do
  @moduledoc "Auth-owned mail intent. Never expose raw recovery tokens in logs or responses."
  @derive {Inspect, except: [:raw]}
  defstruct [:kind, :user_id, :raw, :digest, :locale]
end
