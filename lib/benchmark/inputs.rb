require "benchmark/inputs/version"

module Benchmark

  # Initializes a benchmark Job, and yields the Job to the given block.
  #
  # @example Benchmarking non-destructive operations
  #   Benchmark.inputs(["abc", "aaa", "xyz", ""]) do |job|
  #     job.report("String#tr"){|string| string.tr("a", "A") }
  #     job.report("String#gsub"){|string| string.gsub(/a/, "A") }
  #     job.compare!
  #   end
  #
  # @example Benchmarking destructive operations
  #   Benchmark.inputs(["abc", "aaa", "xyz", ""], dup_inputs: true) do |job|
  #     job.report("String#tr!"){|string| string.tr!("a", "A") }
  #     job.report("String#gsub!"){|string| string.gsub!(/a/, "A") }
  #     job.compare!
  #   end
  #
  # @param values [Array]
  #   Input values to be individually yielded to all {Inputs::Job#report
  #   +report+} blocks
  # @param options [Hash]
  # @option options :dup_inputs [Boolean] (false)
  #   Whether each of +values+ should be +dup+'d before being yielded to
  #   a {Inputs::Job#report +report+} block.  This should be set to true
  #   if any +report+ block destructively modifies its input.
  # @option options :sample_n [Integer] (10)
  #   Number of samples to take when benchmarking
  # @option options :sample_dt [Integer] (200,000 ns)
  #   Approximate duration of time each sample should take when
  #   benchmarking, in nanoseconds
  # @yieldparam job [Benchmark::Inputs::Job]
  # @return [Benchmark::Inputs::Job]
  # @raise [ArgumentError]
  #   if +values+ is empty
  def self.inputs(values, **options)
    job = Inputs::Job.new(values, **options)
    yield job
    job
  end


  module Inputs

    # @!visibility private
    NS_PER_S = 1_000_000_000
    # @!visibility private
    NS_PER_MS = NS_PER_S / 1_000

    class Job

      # @!visibility private
      def initialize(inputs, dup_inputs: false, sample_n: 10, sample_dt: NS_PER_MS * 200)
        raise ArgumentError, "No inputs specified" if inputs.empty?

        @inputs = inputs
        @dup_inputs = dup_inputs
        @sample_n = sample_n
        @sample_dt = sample_dt
        @reports = []
        def_bench!
      end

      # @return [Boolean]
      attr_reader :dup_inputs

      # @param flag [Boolean]
      # @return [Boolean]
      def dup_inputs=(flag)
        @dup_inputs = flag
        def_bench!
        @dup_inputs
      end

      # @return [Integer]
      attr_accessor :sample_n

      # @return [Integer]
      attr_accessor :sample_dt

      # Array of benchmark reports.  Each call to {report} adds an
      # element to this array.
      #
      # @return [Array<Benchmark::Inputs::Report>]
      attr_reader :reports

      # Benchmarks the given block using each of the Job's input values.
      # If {dup_inputs} is true, each input value is +dup+'d before
      # being yielded to the block.  Prints the block's estimated speed
      # (in invocations per second) to +$stdout+, and adds a {Report} to
      # {reports}.
      #
      # @param label [String]
      #   Label for the report
      # @yieldparam input [Object]
      #   One of the Job's input values
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
      # {reports} to +$stdout+.
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

      # The ratio of the speed from the fastest report compared to the
      # speed from this report.  In other words, the "slower than
      # fastest by" multiplier for this report.  Will be +nil+ if the
      # absolute difference in speed between the two reports falls
      # within the combined measurement error.
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

      # The estimated speed for the report, in invocations per second.
      #
      # @return [Float]
      def ips
        @mean
      end

      # The standard deviation of the estimated speed for the report.
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
