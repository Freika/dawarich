defmodule Dawarich.Auth.TwoFactor.Api do
  @moduledoc false
  alias Dawarich.Auth.TwoFactor.{ApiActor, ApiWrite, Secret}
  alias Dawarich.I18n

  def run(action, id, params, context) do
    cond do
      context[:self_hosted] != true ->
        {:replay, :cloud}

      not Secret.available?(Map.get_lazy(context, :env, &System.get_env/0)) ->
        error(503, "two_factor_not_available")

      true ->
        with {:ok, user} <- ApiActor.load(id, context) do
          if ApiActor.password_valid?(user, params["password"]),
            do: dispatch(action, user, params, context),
            else: error(401, "password_required", "provide_your_current_password")
        end
    end
  end

  defp dispatch(:setup, %{otp_required_for_login: true}, _params, _context),
    do: error(409, "two_factor_already_enabled", "disable_2fa_first_to_re_provision_the_secret")

  defp dispatch(:setup, user, _params, context), do: ApiWrite.setup(user, context)

  defp dispatch(:confirm, user, params, context),
    do: ApiWrite.confirm(user, params["otp_code"], context)

  defp error(status, reason), do: {:ok, status, {:object, [{"error", reason}]}}

  defp error(status, reason, key),
    do:
      {:ok, status,
       {:object,
        [{"error", reason}, {"message", I18n.en!("controllers.api.v1.users.two_factor." <> key)}]}}
end
