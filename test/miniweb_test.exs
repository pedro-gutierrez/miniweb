defmodule MiniwebTest do
  use ExUnit.Case
  doctest Miniweb

  test "greets the world" do
    assert Miniweb.hello() == :world
  end
end
