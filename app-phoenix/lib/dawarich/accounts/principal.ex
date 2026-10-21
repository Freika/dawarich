defmodule Dawarich.Accounts.Principal do
  @moduledoc false
  @fields ~w(id first_name last_name email provider theme admin status plan active_until subscription_source changelog_consent points_count)a
  defstruct @fields ++ [:settings, :session_version]
  @private ~w(password api_key token secret authorization credential url)

  def scope(%Dawarich.Accounts.Scope{user: %{id: id} = user, locale: locale}) do
    Dawarich.Accounts.Scope.for_user(
      %__MODULE__{id: id, session_version: version(user), settings: %{}},
      locale
    )
  end

  def scope(_), do: nil

  def project(user) do
    user
    |> Map.take(@fields)
    |> Map.put(:settings, settings(Dawarich.UserSettings.get(user)))
    |> Map.put(:session_version, version(user))
    |> then(&struct(__MODULE__, &1))
  end

  def version(%{session_version: version}) when is_binary(version), do: version

  def version(%{encrypted_password: value}) when is_binary(value),
    do: :crypto.hash(:sha256, String.slice(value, 0, 29)) |> Base.encode16(case: :lower)

  def version(_), do: nil

  def same_identity?(original, current) do
    with left when is_binary(left) <- version(original),
         right when is_binary(right) <- version(current),
         do: Plug.Crypto.secure_compare(left, right),
         else: (_ -> false)
  end

  defp settings(settings) when is_map(settings) do
    settings
    |> Map.reject(fn {key, _} ->
      key = String.downcase(to_string(key))
      Enum.any?(@private, &String.contains?(key, &1))
    end)
    |> Map.new(fn {key, value} -> {key, clean(value)} end)
  end

  defp settings(_), do: :unsupported

  defp clean(value) when is_map(value), do: settings(value)
  defp clean(value) when is_list(value), do: Enum.map(value, &clean/1)
  defp clean(value), do: value
end

defimpl Inspect, for: Dawarich.Accounts.Principal do
  import Inspect.Algebra

  def inspect(principal, opts) do
    fields =
      principal
      |> Map.from_struct()
      |> Map.update!(
        :settings,
        fn settings ->
          case Dawarich.LogRedaction.scrub(settings) do
            settings when is_map(settings) -> Map.delete(settings, "supporter_email")
            settings -> settings
          end
        end
      )

    concat(["#Dawarich.Accounts.Principal<", to_doc(fields, opts), ">"])
  end
end
