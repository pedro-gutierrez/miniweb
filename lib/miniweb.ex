defmodule Miniweb do
  @moduledoc """
  A small and opinionated web framework.

  Usage:

  ```elixir
  defmodule MyApp.Web,
    use Miniweb,
      otp_app: :my_app,
      cookies: [
        secret_key_base: {MyApp, :secret_key_base, []},
        signing_salt: {MyApp, :signing_salt, []},
        encryption_salt: {MyApp, :encryption_salt, []}
      ],
      log: true,
      template_store: :memory, # or :disk
      context: MyApp.MyHandlers,
      handlers: [
        MyApp.MyHandlers.Posts,
        MyApp.MyHandlers.Posts.Id,
        MyApp.MyHandlers.Comments
      ]
  ```
  """

  alias Miniweb.Routes

  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    log = Keyword.get(opts, :log, true)

    # Figure out how session cookies are going be setup. We will need to obtain values for the
    # secret_key_base, the signing salt, and the encryption salt:
    #
    #   * if `nil`, then cookies will be disabled in this router.
    #   * if `true`, then we will use `System.fetch_env!/1` as a default strategy
    #   * otherwise, use the mfas provided by the user
    cookies =
      with true <- Keyword.get(opts, :cookies) do
        Macro.escape(
          secret_key_base: {System, :fetch_env!, ["SECRET_KEY_BASE"]},
          signing_salt: {System, :fetch_env!, ["SIGNING_SALT"]},
          encryption_salt: {System, :fetch_env!, ["ENCRYPTION_SALT"]}
        )
      end

    template_store = Keyword.get(opts, :template_store, :memory)
    conn = Macro.var(:conn, nil)

    handlers =
      opts
      |> Keyword.fetch!(:handlers)
      |> Enum.map(&extract_alias/1)

    # Infer the root context for all handler modules
    # By convention, we look for the handler that has the `Root`
    # bit, and we extract everything before that and we consider that's the context
    context =
      handlers
      |> Enum.map(&Module.split/1)
      |> Enum.find(&Enum.member?(&1, "Root"))
      |> then(fn
        nil ->
          raise "No root handler provided"

        handler ->
          index = Enum.find_index(handler, &(&1 == "Root"))
          Enum.slice(handler, 0, index)
      end)
      |> Module.concat()

    # Draw all routes and generate a router matcher for each route
    routes =
      handlers
      |> Enum.flat_map(&Routes.draw(&1, context: context))
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
      @cookies unquote(cookies)

      if is_list(@cookies) do
        @secret_key_base_m @cookies |> Keyword.fetch!(:secret_key_base) |> elem(0)
        @secret_key_base_f @cookies |> Keyword.fetch!(:secret_key_base) |> elem(1)
        @secret_key_base_a @cookies |> Keyword.fetch!(:secret_key_base) |> elem(2)

        def put_secret_key_base(conn, _) do
          value = apply(@secret_key_base_m, @secret_key_base_f, @secret_key_base_a)

          put_in(conn.secret_key_base, value)
        end

        plug(:put_secret_key_base)

        plug(Plug.Session,
          store: :cookie,
          key: "_miniweb",
          signing_salt: Keyword.fetch!(@cookies, :signing_salt),
          encryption_salt: Keyword.fetch!(@cookies, :encryption_salt),
          http_only: true,
          log: false
        )

        plug(:fetch_session)
      end

      # Build a template store for dev or production
      # according to the caching settings defined by the user
      @template_store unquote(template_store)

      if @template_store == :memory do
        defmodule TemplateStore do
          @moduledoc false
          use Miniweb.Template.Store.Memory,
            otp_app: unquote(otp_app)
        end
      else
        defmodule TemplateStore do
          @moduledoc false
          use Miniweb.Template.Store.Disk,
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
