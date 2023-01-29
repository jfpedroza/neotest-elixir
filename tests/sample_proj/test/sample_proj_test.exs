defmodule SampleProjTest do
  use ExUnit.Case, async: true
  doctest SampleProj

  test "greets the world" do
    assert SampleProj.hello() == :world
  end

  @tag :special
  test "excluded by default" do
    assert SampleProj.hello() == :mundo
  end
end
