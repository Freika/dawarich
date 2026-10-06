defmodule Dawarich.Auth.Providers.OidcAccounts do
  @moduledoc false
  alias Dawarich.Auth.Providers.Accounts

  def resolve(identity, context) do
    allow =
      Map.get(context, :auto_register, System.get_env("OIDC_AUTO_REGISTER", "true") != "false")

    Accounts.resolve(identity, Map.put(context, :allow_registration, allow))
  end
end
