defmodule Miniweb.Template.Tag.Html do
  @moduledoc """
  A Solid custom tag to dynamically resolve values from models, using a level of indirection.
  """
  import NimbleParsec
  import Plug.HTML

  @behaviour Solid.Tag

  alias Solid.Parser.{BaseTag, Argument, Literal}

  @impl true
  def spec(_parser) do
    space = Literal.whitespace(min: 0)

    ignore(BaseTag.opening_tag())
    |> ignore(string("html"))
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

    target = target(context, target)
    prop = prop(context, path)
    value = target |> Map.get(prop, "") |> format() |> maybe_highlight(context)

    [text: value]
  end

  defp maybe_highlight(value, context) do
    case context.counter_vars["highlight"] do
      nil ->
        value

      regex ->
        Regex.replace(regex, value, "<mark>\\0</mark>")
    end
  end

  defp target(context, path), do: context.iteration_vars[path] || context.counter_vars[path]

  defp prop(context, path) do
    if String.contains?(path, ".") do
      path = String.split(path, ".")

      get_in(context.iteration_vars, path) || get_in(context.counter_vars, path)
    else
      path
    end
  end

  defp format(true), do: "Yes"
  defp format(false), do: "No"

  defp format(str) when is_binary(str), do: html_escape(str)

  defp format(num) when is_atom(num) or is_number(num), do: to_string(num)

  defp format(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Europe/Paris")
    |> Calendar.strftime("%a, %B %d %H:%M:%S")
  end

  defp format(json) when is_map(json) do
    json |> Jason.encode!() |> Jason.Formatter.pretty_print() |> format()
  end
end
