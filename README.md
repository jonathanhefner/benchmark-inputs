# benchmark-inputs

Input-focused benchmarking for Ruby.  Given one or more blocks and a
list of inputs to yield to them, benchmark-inputs will measure the speed
(in invocations per second) of each block.  Blocks which execute very
quickly, as in microbenchmarks, are automatically invoked repeatedly to
provide accurate measurements.


## Motivation

I <3 [Fast Ruby][fast-ruby].  By extension, I <3 [benchmark-ips].  But,
for certain usages, benchmark-ips doesn't let me write benchmarks the
way I'd like. Consider the following example, *using benchmark-ips*:

```ruby
require 'benchmark/ips' ### USING benchmark-ips (NOT benchmark-inputs)

STRINGS = ['abc', 'aaa', 'xyz', '']
Benchmark.ips do |job|
  job.report('String#tr'){ STRINGS.each{|s| s.tr('a', 'A') } }
  job.report('String#gsub'){ STRINGS.each{|s| s.gsub(/a/, 'A') } }
  job.compare!
end
```

The calls to `STRINGS.each` introduce performance overhead which skews
the time measurements.  The less time the target function takes, the
more relative overhead, and thus the more skew.  For a microbenchmark
this can be a problem.  A possible workaround is to invoke the function
on each value individually, but that is more verbose and error-prone:

```ruby
require 'benchmark/ips' ### USING benchmark-ips (NOT benchmark-inputs)

s1 = 'abc'; s2 = 'aaa'; s3 = 'xyz'; s4 = ''
Benchmark.ips do |job|
  job.report('String#tr') do
    s1.tr('a', 'A'); s2.tr('a', 'A')
    s3.tr('a', 'A'); s4.tr('a', 'A')
  end
  job.report('String#gsub') do
    s1.gsub(/a/, 'A'); s2.gsub(/a/, 'A')
    s3.gsub(/a/, 'A'); s4.gsub(/a/, 'A')
  end
  job.compare!
end
```

*Enter benchmark-inputs*.  Here is how the same benchmark looks using
this gem: <a name="example1"></a>

```ruby
require 'benchmark/inputs' ### USING benchmark-inputs

Benchmark.inputs(['abc', 'aaa', 'xyz', '']) do |job|
  job.report('String#tr'){|s| s.tr('a', 'A') }
  job.report('String#gsub'){|s| s.gsub(/a/, 'A') }
  job.compare!
end
```

Which prints something like the following to `$stdout`:

```
String#tr
  1387268.0 i/s (±0.49%)
String#gsub
  264307.7 i/s (±1.95%)

Comparison:
    String#tr:   1387268.0 i/s
  String#gsub:    264307.7 i/s - 5.25x slower
```


### Benchmarking destructive operations

Destructive operations also pose a challenge for microbenchmarks.  Each
invocation needs to operate on the same data, but `dup`ing the data
introduces too much overhead and skew.

benchmark-inputs' solution is to estimate the overhead incurred by
`dup`, and exclude that from time measurements.  Because the benchmark
job already controls the input data, all of this can be handled with a
single configuration line:

```ruby
require 'benchmark/inputs'

Benchmark.inputs(['abc', 'aaa', 'xyz', '']) do |job|
  job.dup_inputs = true  # <--- single configuration line
  job.report('String#tr!'){|s| s.tr!('a', 'A') }
  job.report('String#gsub!'){|s| s.gsub!(/a/, 'A') }
  job.compare!
end
```

Which prints out something like:

```
String#tr!
  1793132.0 i/s (±0.46%)
String#gsub!
  281588.6 i/s (±0.49%)

Comparison:
    String#tr!:   1793132.0 i/s
  String#gsub!:    281588.6 i/s - 6.37x slower
```

That shows a slightly larger performance gap than the previous
benchmark.  This makes sense because the overhead of allocating new
strings--previously via a non-bang method, but now via `dup`--is now
excluded from the timings.  Thus, the speed of `tr!` relative to `gsub!`
is further emphasized.


## Limitations

`Benchmark.inputs` generates code based on the array of input values it
is given.  Each input value becomes a local variable.  While there is
theoretically no limit to the number of local variables that can be
generated, more than a few hundred may slow down the benchmark.  But,
because input values are used to represent different scenarios rather
than control the number of invocations, this limitation shouldn't pose a
problem.


## Installation

    $ gem install benchmark-inputs


## Usage

See the [example above](#example1), or check the
[documentation](http://www.rubydoc.info/gems/benchmark-inputs).


## License

[MIT License](http://opensource.org/licenses/MIT)




[fast-ruby]: https://github.com/JuanitoFatas/fast-ruby
[benchmark-ips]: https://github.com/evanphx/benchmark-ips
