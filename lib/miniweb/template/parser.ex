defmodule Miniweb.Template.Parser do
  @moduledoc """
  Adds a some custom tags to Solid
  """
  use Solid.Parser.Base,
    custom_tags: [
      Miniweb.Template.Tag.CsrfToken,
      Miniweb.Template.Tag.Html,
      Miniweb.Template.Tag.Slot
    ]
end
