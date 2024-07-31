defmodule Miniweb.Template.Slot do
  @moduledoc """
  A Solid custom tag for layouts

  Similar to the built-in `render` tag, but slightly more dynamic
  """
  import NimbleParsec

  @behaviour Solid.Tag

  alias Miniweb.Template
  alias Solid.Parser.{BaseTag, Argument, Literal}

  @impl true
  def spec(_parser) do
    space = Literal.whitespace(min: 0)

    ignore(BaseTag.opening_tag())
    |> ignore(string("slot"))
    |> ignore(space)
    |> tag(Argument.argument(), :template)
    |> tag(
      optional(
        ignore(string(","))
        |> ignore(space)
        |> concat(Argument.named_arguments())
      ),
      :arguments
    )
    |> ignore(space)
    |> ignore(BaseTag.closing_tag())
  end

  @impl true
  def render(raw, context, opts) do
    slot = raw[:template][:value]
    {named, data} = Map.pop(context.counter_vars, slot, slot)
    text = Template.render_named!(named, data, opts)

    [text: text]
  end
end
