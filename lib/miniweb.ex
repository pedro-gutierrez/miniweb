defmodule Miniweb do
  @moduledoc """
  A small and opinionated web framework.

  Usage:

  ```elixir
  defmodule MyApp.Web,
    use Miniweb,
      otp_app: :my_app,
      sessions: true,
      log: true,
      cache_templates: true,
      context: MyApp.MyHandlers,
      handlers: [
        MyApp.MyHandlers.Posts,
        MyApp.MyHandlers.Posts.Id,
        MyApp.MyHandlers.Comments
      ]
  ```
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    log = Keyword.get(opts, :log, true)
    sessions = Keyword.get(opts, :sessions, true)
    cache_templates = Keyword.get(opts, :cache_templates, true)
    context = opts |> Keyword.fetch!(:context) |> extract_alias()
    conn = Macro.var(:conn, nil)

    routes =
      opts
      |> Keyword.get(:handlers, [])
      |> Enum.map(&extract_alias/1)
      |> Enum.flat_map(& &1.routes(context))
      |> Enum.map(fn {method, path, handler} ->
        quote do
          unquote(method)(unquote(path),
            do:
              unquote(conn)
              |> unquote(handler).unquote(method)(unquote(conn).params)
              |> do_response(unquote(conn))
          )
        end
      end)

    quote do
      use Plug.Router

      # Optional request logger. If miniweb is being used from within a larger Phoenix
      # application, then this might not be necessary
      @log unquote(log)

      if @log, do: plug(Miniweb.Logger)

      # Configure session management using cookies.
      # This is relevant when Miniweb is used standalone, ie, outside a phoenix application.
      # If using Phoenix, chances are that sessions configuration is already made in the
      # Phoenix endpoint, and in that case, there is no need to do it again here
      @sessions unquote(sessions)

      if @sessions do
        def put_secret_key_base(conn, _) do
          value =
            unquote(otp_app)
            |> Application.fetch_env!(Miniweb)
            |> Keyword.fetch!(:secret_key_base)

          put_in(conn.secret_key_base, value)
        end

        plug(:put_secret_key_base)

        plug(Plug.Session,
          store: :cookie,
          key: "_miniweb",
          signing_salt: "Kp4e0ocZ",
          encryption_salt: "Y2e0yz2j",
          http_only: true,
          log: false
        )

        plug(:fetch_session)
      end

      # Build a template store for dev or production
      # according to the caching settings defined by the user
      @cache_templates unquote(cache_templates)

      if @cache_templates do
        defmodule TemplateStore do
          use Miniweb.Template.MemoryStore,
            otp_app: unquote(otp_app)
        end
      else
        defmodule TemplateStore do
          use Miniweb.Template.DiskStore,
            otp_app: unquote(otp_app)
        end
      end

      # Serve static assets from the user's app priv directory
      plug(Plug.Static, at: "/static", from: {unquote(otp_app), "priv/static"})

      plug(:match)
      plug(:dispatch)

      # Application routes from handlers
      unquote_splicing(routes)

      # Catch all route, that renders a styled not found page
      # using a simple layout
      @not_found_opts [
        status: 404,
        template: "not_found",
        layout: "layouts/simple"
      ]

      match _ do
        do_response({:render, @not_found_opts}, unquote(conn))
      end

      # Helper functions to either building html markup
      # or sending a redirect back to the browser
      defp do_response({:render, opts}, conn) do
        template = Keyword.fetch!(opts, :template)

        layout = opts[:layout] || "layouts/default"

        extra =
          unquote(otp_app)
          |> Application.get_env(Miniweb, [])
          |> Keyword.get(:extra, %{})

        data = opts[:data] || %{}

        data =
          extra
          |> Map.merge(data)
          |> Map.put("main", template)

        html =
          Miniweb.Template.render_named!(layout, data, template_store: __MODULE__.TemplateStore)

        status = opts[:status] || 200

        conn
        |> put_session(opts)
        |> put_resp_content_type("text/html")
        |> send_resp(status, html)
      end

      defp do_response({:redirect, opts}, conn) do
        url = Keyword.fetch!(opts, :url)
        status = Keyword.get(opts, :status, 303)

        conn
        |> put_resp_content_type("text/text")
        |> put_resp_header("Location", url)
        |> put_session(opts)
        |> send_resp(status, "")
      end

      defp put_session(conn, opts) do
        session = opts[:session] || %{}

        Enum.reduce(session, conn, fn {key, value}, acc ->
          put_session(acc, key, value)
        end)
      end
    end
  end

  defp extract_alias({:__aliases__, _, parts}), do: Module.concat(parts)
  defp extract_alias(module) when is_atom(module), do: module
end
