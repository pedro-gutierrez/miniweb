defmodule Miniweb.MixProject do
  use Mix.Project

  def project do
    [
      app: :miniweb,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:inflex, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0.0-rc.6"},
      {:plug, "~> 1.16"},
      {:solid, "~> 0.15"}
    ]
  end
end
