require "test_helper"

class Benchmark::InputsTest < Minitest::Test

  def test_that_it_has_a_version_number
    refute_nil ::Benchmark::Inputs::VERSION
  end

  def test_basic_usage
    counters = [0, 0, 0, 0]
    reports = nil

    out, err = capture_io do
      reports = Benchmark.inputs([0, 1]) do |job|
        job.report("aaa"){|i| counters[i] += 1 }
        job.report("bbb"){|i| counters[i + 2] += 1 }
        job.compare!
      end.reports
    end

    assert_equal 2, reports.length
    assert_equal "aaa", reports[0].label
    assert_equal "bbb", reports[1].label

    assert_operator counters[0], :>, 0
    assert_equal counters[0], counters[1]
    assert_operator counters[2], :>, 0
    assert_equal counters[2], counters[3]

    assert_match "Comparison", out
    assert_match "aaa", out
    assert_match "bbb", out
    assert_empty err
  end

  def test_dup_inputs
    strs = ["a", "b"]
    reports = nil

    out, err = capture_io do
      reports = Benchmark.inputs(strs) do |job|
        job.dup_inputs = true
        job.report("tr!"){|s| s.tr!("a-z", "_") }
        job.report("gsub!"){|s| s.gsub!(/[a-z]/, "_") }
        job.compare!
      end.reports
    end

    assert_equal 2, reports.length
    refute_empty out
    assert_empty err

    assert_equal "a", strs[0]
    assert_equal "b", strs[1]
  end

end
