require "benchmark/inputs/version"

module Benchmark

  # Initializes a benchmark job with the given inputs and yields that
  # job to the given block.
  #
  # @example Benchmarking non-destructive operations
  #   Benchmark.inputs(["abc", "aaa", "xyz", ""]) do |job|
  #     job.report("String#tr"){|s| s.tr("a", "A") }
  #     job.report("String#gsub"){|s| s.gsub(/a/, "A") }
  #     job.compare!
  #   end
  #
  # @example Benchmarking destructive operations
  #   Benchmark.inputs(["abc", "aaa", "xyz", ""], dup_inputs: true) do |job|
  #     job.report("String#tr!"){|s| s.tr!("a", "A") }
  #     job.report("String#gsub!"){|s| s.gsub!(/a/, "A") }
  #     job.compare!
  #   end
  #
  # @param values [Array]
  #   input values to yield to each benchmark action
  # @param options [Hash]
  # @option options :dup_inputs [Boolean]
  #   whether input values will be +dup+-ed before they are passed to a
  #   {Inputs::Job#report} block
  # @option options :sample_n [Integer]
  #   number of samples to take when benchmarking
  # @option options :sample_dt [Integer]
  #   approximate duration of time (in nanoseconds) each sample should
  #   take when benchmarking
  # @yield [job]
  #   configures job and runs benchmarks
  # @yieldparam job [Benchmark::Inputs::Job]
  #   benchmark runner
  # @return [Benchmark::Inputs::Job]
  #   benchmark runner
  # @raise [ArgumentError]
  #   if +values+ is empty
  def self.inputs(values, **options)
    job = Inputs::Job.new(values, **options)
    yield job
    job
  end


  module Inputs

    NS_PER_S = 1_000_000_000
    NS_PER_MS = NS_PER_S / 1_000

    class Job

      # @param inputs [Array]
      #   input values to yield to each benchmark action
      # @param dup_inputs [Boolean]
      #   whether input values will be +dup+-ed before they are passed
      #   to a {report} block
      # @param sample_n [Integer]
      #   number of samples to take when benchmarking
      # @param sample_dt [Integer]
      #   approximate duration of time (in nanoseconds) each sample
      #   should take when benchmarking
      # @raise [ArgumentError]
      #   if +inputs+ is empty
      def initialize(inputs, dup_inputs: false, sample_n: 10, sample_dt: NS_PER_MS * 200)
        raise ArgumentError, "No inputs specified" if inputs.empty?

        @inputs = inputs
        @dup_inputs = dup_inputs
        @sample_n = sample_n
        @sample_dt = sample_dt
        @reports = []
        def_bench!
      end

      # Indicates whether input values will be +dup+-ed before they are
      # passed to a {report} block.  Defaults to +false+.  This should
      # be set to +true+ if {report} blocks destructively modify their
      # arguments.
      #
      # @return [Boolean]
      attr_reader :dup_inputs

      # See {dup_inputs}.
      #
      # @param flag [Boolean]
      # @return [Boolean]
      def dup_inputs=(flag)
        @dup_inputs = flag
        def_bench!
        @dup_inputs
      end

      # The number of samples to take when benchmarking.  Defaults to 10.
      #
      # @return [Integer]
      attr_accessor :sample_n

      # The approximate duration of time (in nanoseconds) each sample
      # should take when benchmarking.  Defaults to 200,000 nanoseconds.
      #
      # @return [Integer]
      attr_accessor :sample_dt

      # Array of benchmark reports.  Each call to {report} adds an
      # element to this array.
      #
      # @return [Array<Benchmark::Inputs::Report>]
      attr_reader :reports

      # Benchmarks the given block using the previously provided input
      # values.  If {dup_inputs} is set to true, each input value is
      # +dup+'d before being passed to the block.  The block's
      # iterations per second (i/s) is printed to +$stdout+, and a
      # {Report} is added to {reports}.
      #
      # @param label [String]
      #   label for the benchmark
      # @yield [input]
      #   action to benchmark
      # @yieldparam input [Object]
      #   one of the initially provided input values
      # @return [void]
      def report(label)
        # estimate repititions
        reps = 1
        reps_time = 0
        while reps_time < @sample_dt
          reps_time = bench(reps){|x| yield(x) }
          reps *= 2
        end
        reps = ((reps / 2) * (reps_time.to_f / @sample_dt)).ceil

        # benchmark
        r = Report.new(label, reps * @inputs.length)
        i = @sample_n
        GC.start()
        while i > 0
          r.add_sample(bench(reps){|x| yield(x) } - bench(reps){|x| x })
          i -= 1
        end

        $stdout.puts(r.label)
        $stdout.printf("  %.1f i/s (\u00B1%.2f%%)\n", r.ips, r.stddev / r.ips * 100)
        @reports << r
      end

      # Prints the relative speeds (from fastest to slowest) of all
      # {report}-ed benchmarks to +$stdout+.
      #
      # @return [void]
      def compare!
        return $stdout.puts("Nothing to compare!") if @reports.empty?

        @reports.sort_by!{|r| -r.ips }
        @reports.each{|r| r.slower_than!(@reports.first) }

        max_label_len = @reports.map{|r| r.label.length }.max
        format = "  %#{max_label_len}s:  %10.1f i/s"

        $stdout.puts("\nComparison:")
        @reports.each_with_index do |r, i|
          $stdout.printf(format, r.label, r.ips)
          if r.ratio
            $stdout.printf(" - %.2fx slower", r.ratio)
          elsif i > 0
            $stdout.printf(" - same-ish: difference falls within error")
          end
          $stdout.puts
        end
        $stdout.puts
      end

      private

      def def_bench!
        assigns = @inputs.each_index.map do |i|
          "x#{i} = @inputs[#{i}]"
        end.join(";")

        yields = @inputs.each_index.map do |i|
          dup_inputs ? "yield(x#{i}.dup)" : "yield(x#{i})"
        end.join(";")

        code = <<-CODE
          def bench(reps)
            #{assigns}
            i = reps
            before_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
            while i > 0
              #{yields}
              i -= 1
            end
            after_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
            after_time - before_time
          end
        CODE

        instance_eval{ undef :bench } if self.respond_to?(:bench)
        instance_eval(code)
      end
    end


    class Report
      # The label for the report.
      #
      # @return [String]
      attr_reader :label

      # The ratio of iterations per second for this report compared to
      # the fastest report.  Will be +nil+ if the difference between the
      # two falls within the combined measurement error.
      #
      # This value is set by {Benchmark::Inputs::Job#compare!}.
      #
      # @return [Float, nil]
      attr_reader :ratio

      # @!visibility private
      def initialize(label, invocs_per_sample)
        @label = label.to_s
        @invocs_per_sample = invocs_per_sample.to_f
        @ratio = nil

        @n = 0
        @mean = 0.0
        @m2 = 0.0
      end

      # @!visibility private
      def add_sample(time_ns)
        sample_ips = @invocs_per_sample * NS_PER_S / time_ns

        # see https://en.wikipedia.org/wiki/Algorithms_for_calculating_variance#Online_algorithm
        # or Knuth's TAOCP vol 2, 3rd edition, page 232
        @n += 1
        delta = sample_ips - @mean
        @mean += delta / @n
        @m2 += delta * (sample_ips - @mean)
        @stddev = nil
      end

      # The estimated iterations per second for the report.
      #
      # @return [Float]
      def ips
        @mean
      end

      # The {ips} standard deviation.
      #
      # @return [Float]
      def stddev
        @stddev ||= @n < 2 ? 0.0 : Math.sqrt(@m2 / (@n - 1))
      end

      # @!visibility private
      def slower_than!(faster)
        @ratio = overlap?(faster) ? nil : (faster.ips / self.ips)
      end

      # @!visibility private
      def overlap?(faster)
        (faster.ips - faster.stddev) <= (self.ips + self.stddev)
      end
    end

  end

end
