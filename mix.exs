defmodule Ekv.MixProject do
  use Mix.Project

  def project() do
    [
      app: :ekv,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application() do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps(), do: [{:mix_test_watch, "~> 0.8", only: :dev, runtime: false}]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
