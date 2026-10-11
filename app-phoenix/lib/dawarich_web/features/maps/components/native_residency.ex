defmodule DawarichWeb.NativeResidency do
  @moduledoc false
  use Phoenix.Component

  attr :residency, :map, default: nil
  attr :locale, :string, required: true

  def card(%{residency: nil} = assigns), do: ~H""

  def card(assigns) do
    ~H"""
    <section id="native-residency" class="min-w-0" data-residency-year={@residency.year}>
      <DawarichWeb.ResidencyFrame.content {Map.put(@residency, :locale, @locale)} />
    </section>
    """
  end
end
