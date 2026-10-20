defmodule Dawarich.Test.SettingsParity do
  @moduledoc false

  def dump(name, rails, phoenix) do
    if directory = System.get_env("PARITY_DUMP") do
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "#{name}.rails.html"), rails)
      File.write!(Path.join(directory, "#{name}.phoenix.html"), phoenix)
    end
  end
end
