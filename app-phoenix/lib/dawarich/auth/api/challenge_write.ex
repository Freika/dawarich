defmodule Dawarich.Auth.Api.ChallengeWrite do
  @moduledoc false
  alias Dawarich.Auth.Api.ChallengeCache
  alias Dawarich.Auth.Otp.Completion

  def commit(prepared, context) do
    user = Completion.consume(prepared, context)
    ChallengeCache.mark(prepared.jti, context)
    Completion.reset_otp(user, context)
    {:ok, prepared.payload}
  end
end
