defmodule Miniweb.Response do
  @moduledoc "Response helpers"
  import Plug.Conn

  alias Miniweb.Template

  @doc """
  Handle a response

  Most of the time, rendering a template or sending a redirect
  """
  def send_response(opts, conn) do
    opts
    |> Keyword.fetch!(:action)
    |> send_response(opts, conn)
  end

  defp send_response(:render, opts, conn) do
    template = Keyword.fetch!(opts, :template)

    layout = opts[:layout] || "layouts/default"

    data =
      opts
      |> Keyword.get(:data, %{})
      |> Map.put("main", template)
      |> Map.put("basePath", opts[:base_path] || "")
      |> Map.put("title", opts[:title] || "Miniweb")

    html = Template.render_named!(layout, data, opts)

    conn
    |> put_session(opts)
    |> send_html(html, opts)
  end

  defp send_response(:redirect, opts, conn) do
    url = Keyword.fetch!(opts, :url)
    status = Keyword.get(opts, :status, 303)

    conn
    |> put_resp_content_type("text/text")
    |> put_resp_header("Location", url)
    |> put_session(opts)
    |> send_resp(status, "")
  end

  defp send_html(conn, html, opts) do
    status = opts[:status] || 200

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, html)
  end

  defp put_session(conn, opts) do
    session = opts[:session] || %{}

    Enum.reduce(session, conn, fn {key, value}, acc ->
      put_session(acc, key, value)
    end)
  end
end
