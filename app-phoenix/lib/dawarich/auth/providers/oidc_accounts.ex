defmodule Dawarich.Auth.Providers.OidcAccounts do
  @moduledoc false
  alias Dawarich.Auth.Providers.Accounts

  def resolve(identity, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    allow = Map.get(context, :auto_register, Map.get(env, "OIDC_AUTO_REGISTER", "true") == "true")

    Accounts.resolve(identity, Map.put(context, :allow_registration, allow))
  end
end
