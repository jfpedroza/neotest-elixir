defmodule SampleProj.ParseTest do
  use ExUnit.Case, async: true

  doctest SampleProj

  test "a test without describe" do
    IO.puts("This is some output, where is it?")
    assert SampleProj.hello() == :world
  end

  describe "simple tests" do
    test "the most basic test" do
      assert SampleProj.hello() == :world
    end

    test "test with a context", %{} do
      assert SampleProj.hello() == :world
    end
  end

  describe "dynamic tests" do
    for i <- 1..3 do
      test "#{i} at the start" do
        assert SampleProj.hello() == :world
      end

      test "in the #{i} middle" do
        assert SampleProj.hello() == :world
      end

      test "at the end #{i}" do
        assert SampleProj.hello() == :world
      end

      test "#{i}" do
        assert SampleProj.hello() == :world
      end

      for j <- [:foo, :bar] do
        test "#{i} nested #{j} test" do
          assert SampleProj.hello() == :world
        end
      end
    end

    for k <- ["foo", "bar"] do
      test k do
        assert SampleProj.hello() == :world
      end
    end
  end
end
