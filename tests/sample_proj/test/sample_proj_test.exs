defmodule SampleProjTest do
  use ExUnit.Case, async: true
  doctest SampleProj

  test "greets the world" do
    assert SampleProj.hello() == :world
  end
end
