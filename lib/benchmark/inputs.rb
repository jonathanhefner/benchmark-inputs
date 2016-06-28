require 'benchmark/inputs/version'

module Benchmark

  def self.inputs(vals)
    job = Inputs::Job.new(vals)
    yield job
    job
  end


  module Inputs

    NS_PER_S = 1_000_000_000
    NS_PER_MS = NS_PER_S / 1_000

    class Job
      attr_accessor :sample_n, :sample_dt
      attr_reader   :dup_inputs, :reports

      def initialize(inputs)
        @inputs = inputs
        @dup_inputs = false
        @sample_n = 10
        @sample_dt = NS_PER_MS * 200
        @reports = []
        def_bench!
      end

      def dup_inputs=(val)
        @dup_inputs = val
        def_bench!
        @dup_inputs
      end

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
        $stdout.printf("  %.1f i/s (\u00B1%.2f%%)\n", r.ips, r.stddev / r.ips)
        @reports << r
        r
      end

      def compare!
        return $stdout.puts('Nothing to compare!') if @reports.empty?

        @reports.sort_by!{|r| -r.ips }
        @reports.each{|r| r.slower_than!(@reports.first) }

        max_label_len = @reports.map{|r| r.label.length }.max
        format = "  %#{max_label_len}s:  %10.1f i/s"

        $stdout.puts("\nComparison:")
        @reports.each_with_index do |r, i|
          $stdout.printf(format, r.label, r.ips)
          if r.ratio
            $stdout.printf(' - %.2fx slower', r.ratio)
          elsif i > 0
            $stdout.printf(' - same-ish: difference falls within error')
          end
          $stdout.puts
        end
        $stdout.puts
      end

      private

      def def_bench!
        assigns = @inputs.each_index.map do |i|
          "x#{i} = @inputs[#{i}]"
        end.join(';')

        yields = @inputs.each_with_index.map do |x, i|
          dup = (@dup_inputs && x.respond_to?(:dup)) ? '.dup' : ''
          "yield(x#{i}#{dup})"
        end.join(';')

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
      attr_reader :label, :ratio

      def initialize(label, invocs_per_sample)
        @label = label.to_s
        @invocs_per_sample = invocs_per_sample.to_f
        @ratio = nil

        @n = 0
        @mean = 0.0
        @m2 = 0.0
      end

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

      def ips
        @mean
      end

      def stddev
        @stddev ||= @n < 2 ? 0.0 : Math.sqrt(@m2 / (@n - 1))
      end

      def slower_than!(faster)
        @ratio = overlap?(faster) ? nil : (faster.ips / self.ips)
      end

      def overlap?(faster)
        (faster.ips - faster.stddev) <= (self.ips + self.stddev)
      end
    end

  end

end
