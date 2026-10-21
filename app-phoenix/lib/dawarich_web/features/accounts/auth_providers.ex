defmodule DawarichWeb.AuthProviders do
  @moduledoc false
  use DawarichWeb, :html

  attr :providers, :list, required: true
  attr :wrapper_class, :string, default: nil

  def buttons(assigns) do
    ~H"""
    <div :for={provider <- @providers} {if @wrapper_class, do: %{class: @wrapper_class}, else: %{}}>
      <form
        action={provider.action}
        method={String.downcase(provider.method)}
        data-auth-form
        class="button_to"
      >
        <button type="submit" class={"btn w-full gap-2 " <> provider_class(provider.action)}>
          <DawarichWeb.Icon.brand
            :if={provider_brand(provider.action)}
            name={provider_brand(provider.action)}
            class="size-5"
          />{provider.label}
        </button>
        <input
          :if={provider.method == "POST"}
          type="hidden"
          name="authenticity_token"
          value={provider.csrf}
        />
      </form>
    </div>
    """
  end

  defp provider_brand(action) do
    case List.last(String.split(action, "/")) do
      "github" -> "github"
      "google_oauth2" -> "google"
      "apple" -> "apple"
      _ -> nil
    end
  end

  defp provider_class(action) do
    case provider_brand(action) do
      "github" -> "bg-[#24292f] text-white hover:bg-[#383f47] border-[#24292f]"
      "google" -> "bg-white text-gray-700 border border-gray-300 hover:bg-gray-50"
      "apple" -> "bg-black text-white hover:bg-gray-900 border-black"
      _ -> "btn-primary"
    end
  end
end
