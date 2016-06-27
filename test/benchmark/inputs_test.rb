require 'test_helper'

class Benchmark::InputsTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Benchmark::Inputs::VERSION
  end
end
