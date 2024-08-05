defmodule Miniweb.Template.Tag.Get do
  @moduledoc """
  A Solid custom tag to dynamically resolve values from models, using a level of indirection.
  """
  import NimbleParsec

  @behaviour Solid.Tag

  alias Solid.Parser.{BaseTag, Argument, Literal}

  @impl true
  def spec(_parser) do
    space = Literal.whitespace(min: 0)

    ignore(BaseTag.opening_tag())
    |> ignore(string("get"))
    |> ignore(space)
    |> tag(Argument.argument(), :path)
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
  def render(raw, context, _opts) do
    path = raw[:path][:value]
    ["at", {:field, [target]}] = raw[:arguments][:named_arguments]
    iteration_vars = Map.fetch!(context, :iteration_vars)
    target = Map.fetch!(iteration_vars, target)
    path = String.split(path, ".")
    prop = get_in(iteration_vars, path)
    value = target |> Map.get(prop, "") |> format()

    value =
      case context.counter_vars["searchText"] do
        "" ->
          value

        search_text ->
          search_text
          |> Regex.compile!("i")
          |> Regex.replace(value, "<mark>\\0</mark>")
      end

    [text: value]
  end

  defp format(true), do: "Yes"
  defp format(false), do: "No"

  defp format(str) when is_binary(str), do: str

  defp format(num) when is_atom(num) or is_number(num), do: to_string(num)

  defp format(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Europe/Paris")
    |> Calendar.strftime("%a, %B %d %H:%M:%S")
  end
end
