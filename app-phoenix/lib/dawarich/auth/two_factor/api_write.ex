defmodule Dawarich.Auth.TwoFactor.ApiWrite do
  @moduledoc false
  alias Dawarich.Auth.TwoFactor.{Secret, Totp}
  alias Dawarich.Repo

  def setup(user, context) do
    secret =
      Totp.generate_secret(
        Map.get(context, :secret_entropy, fn -> :crypto.strong_rand_bytes(20) end).()
      )

    {:ok, ciphertext} = Secret.encrypt(secret, Map.get_lazy(context, :env, &System.get_env/0))
    user = persist(user, %{otp_secret: ciphertext}, context)

    {:ok, 200,
     {:object,
      [{"provisioning_uri", Totp.provisioning_uri(secret, user.email)}, {"secret", secret}]}}
  end

  defp persist(user, changes, context) do
    changes = Map.put(changes, :updated_at, Map.get(context, :clock, &DateTime.utc_now/0).())
    user |> Ecto.Changeset.change(changes) |> Map.get(context, :repo, Repo).update!(log: false)
  end
end
