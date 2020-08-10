# benchmark-inputs [![Build Status](https://travis-ci.org/jonathanhefner/benchmark-inputs.svg?branch=master)](https://travis-ci.org/jonathanhefner/benchmark-inputs)

Input-focused benchmarking for Ruby.  Given one or more blocks and an
array of inputs to yield to each of them, benchmark-inputs will measure
the speed (in invocations per second) of each block.  Blocks which
execute very quickly, as in microbenchmarks, are automatically invoked
repeatedly to provide accurate measurements.


## Motivation

I <3 [Fast Ruby][fast-ruby].  By extension, I <3 [benchmark-ips].  But,
for some use cases, benchmark-ips doesn't let me write benchmarks the
way I'd like.  Consider the following example, *using benchmark-ips*:

```ruby
require "benchmark/ips" ### USING benchmark-ips (NOT benchmark-inputs)

STRINGS = ["abc", "aaa", "xyz", ""]
Benchmark.ips do |job|
  job.report("String#tr"){ STRINGS.each{|string| string.tr("a", "A") } }
  job.report("String#gsub"){ STRINGS.each{|string| string.gsub(/a/, "A") } }
  job.compare!
end
```

The calls to `STRINGS.each` introduce performance overhead that skews
the time measurements.  The less time the target function takes, the
more relative overhead, and thus more skew.  For a microbenchmark this
can be a problem.  A possible workaround is to invoke the function on
each value individually, but that is more verbose and more error-prone:

```ruby
require "benchmark/ips" ### USING benchmark-ips (NOT benchmark-inputs)

string1, string2, string3, string4 = ["abc", "aaa", "xyz", ""]
Benchmark.ips do |job|
  job.report("String#tr") do
    string1.tr("a", "A")
    string2.tr("a", "A")
    string3.tr("a", "A")
    string4.tr("a", "A")
  end
  job.report("String#gsub") do
    string1.gsub(/a/, "A")
    string2.gsub(/a/, "A")
    string3.gsub(/a/, "A")
    string4.gsub(/a/, "A")
  end
  job.compare!
end
```


## Usage

*Enter benchmark-inputs*.  Here is how the same benchmark looks using
this gem:

```ruby
require "benchmark/inputs" ### USING benchmark-inputs

Benchmark.inputs(["abc", "aaa", "xyz", ""]) do |job|
  job.report("String#tr"){|string| string.tr("a", "A") }
  job.report("String#gsub"){|string| string.gsub(/a/, "A") }
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

benchmark-inputs' solution is to estimate the overhead incurred by each
`dup`, and exclude that from the time measurements.  Because the
benchmark job already controls the input data, everything can be handled
behind the scenes.  To enable this, use the `dup_inputs` option:

```ruby
require "benchmark/inputs"

Benchmark.inputs(["abc", "aaa", "xyz", ""], dup_inputs: true) do |job|
  job.report("String#tr!"){|string| string.tr!("a", "A") }
  job.report("String#gsub!"){|string| string.gsub!(/a/, "A") }
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

The above shows a slightly larger performance gap than the previous
benchmark.  This makes sense because the overhead of allocating new
strings -- previously via a non-bang method, but now via `dup` -- is now
excluded from the timings.  Thus, the speed of `tr!` relative to `gsub!`
is further emphasized.


## API

See the [API documentation](https://www.rubydoc.info/gems/benchmark-inputs).


## Limitations

`Benchmark.inputs` generates code based on the array of input values it
is given.  Each input value becomes a local variable.  While there is
theoretically no limit to the number of local variables that can be
generated, more than a few hundred may slow down the benchmark.  But,
because input values are used to represent different scenarios rather
than control the number of invocations, this limitation should not pose
a problem.


## Installation

Install the [gem](https://rubygems.org/gems/benchmark-inputs):

```bash
$ gem install benchmark-inputs
```

Then require in your benchmark script:

```ruby
require "benchmark/inputs"
```


## License

[MIT License](LICENSE.txt)




[fast-ruby]: https://github.com/JuanitoFatas/fast-ruby
[benchmark-ips]: https://rubygems.org/gems/benchmark-ips
