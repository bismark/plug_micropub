defmodule PlugMicropub.MixProject do
  use Mix.Project

  def project do
    [
      app: :plug_micropub,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "PlugMicropub",
      description: "A small library for building a Plug-based Micropub server.",
      source_url: "https://github.com/bismark/plug_micropub",
      docs: [main: "readme", extras: ["README.md"]],
      package: [
        name: "plug_micropub",
        licenses: ["BSD 3-Clause"],
        maintainers: ["Ryan Johnson"],
        links: %{github: "https://github.com/bismark/plug_micropub"}
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.5"},
      {:ex_doc, "~> 0.18.3", only: :dev, runtime: false}
    ]
  end
end
