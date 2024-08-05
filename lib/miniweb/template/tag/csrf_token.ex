defmodule Miniweb.Template.Tag.CsrfToken do
  @moduledoc """
  A Solid custom tag that renders a hidden input field that adds a csfr token in forms
  """
  import NimbleParsec
  import Plug.CSRFProtection, only: [get_csrf_token: 0]

  alias Solid.Parser.{BaseTag, Literal}
  @behaviour Solid.Tag

  @impl true
  def spec(_parser) do
    space = Literal.whitespace(min: 0)

    ignore(BaseTag.opening_tag())
    |> ignore(string("csrf_token"))
    |> ignore(space)
    |> ignore(BaseTag.closing_tag())
  end

  @impl true
  def render(_raw, _context, _opts) do
    text = "<input name=\"_csrf_token\" type=\"hidden\" value=\"#{get_csrf_token()}\">"

    [text: text]
  end
end
