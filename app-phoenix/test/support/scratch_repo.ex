defmodule Dawarich.ScratchRepo do
  use Ecto.Repo, otp_app: :dawarich, adapter: Ecto.Adapters.Postgres
end

defmodule Dawarich.ScratchCaseRepo do
  use Ecto.Repo, otp_app: :dawarich, adapter: Ecto.Adapters.Postgres
end
