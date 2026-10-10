defmodule Dawarich.Imports.StorageContext do
  @moduledoc false
  alias Dawarich.Storage.ImportServices

  def storage do
    case Application.get_env(:dawarich, :imports_storage) do
      nil ->
        Map.get(services(), current_service()) ||
          raise ArgumentError, "Current Rails import storage service is not configured"

      config ->
        config
    end
  end

  def services do
    catalog =
      Application.get_env(:dawarich, :imports_services) ||
        ImportServices.configured!(System.get_env(), Dawarich.RailsRoot.join(""))

    case Application.get_env(:dawarich, :imports_storage) do
      nil -> catalog
      config -> Map.put(catalog, Map.get(config, :stored_service, config.service), config)
    end
  end

  defp current_service do
    env = System.get_env("RAILS_ENV") || System.get_env("RACK_ENV") || System.get_env("MIX_ENV")
    if env == "test", do: "test", else: System.get_env("STORAGE_BACKEND", "local")
  end
end
