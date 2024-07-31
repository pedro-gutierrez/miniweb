defmodule Miniweb.Template.Parser do
  @moduledoc """
  Adds a some custom tags to Solid
  """
  use Solid.Parser.Base, custom_tags: [Miniweb.Template.Slot]
end
