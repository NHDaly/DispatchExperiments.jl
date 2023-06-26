# DispatchExperiments.jl

Implementation of polymorphic single dispatch via Virtual Tables (a la C++'s polymorphism) in Julia.

This could be used for a baseline comparison of the performance of dynamic multiple dispatch in julia against a single dispatch case.

Here is the current state of the comparisons, per the tests.
Julia's dispatch is the first number, and the package's dispatch is the second number:
```julia
13:01:07 | START (3/7) test item "Perf tests - mutable, with return value" at src/single-dispatch-tests.jl:74
  0.032588 seconds (659.00 k allocations: 10.056 MiB)
  0.008757 seconds
13:01:07 | DONE  (3/7) test item "Perf tests - mutable, with return value" 0.1 secs (45.3% compile), 782.97 K allocs (19.125 MB)
13:01:07 | START (4/7) test item "Perf tests - mutable, no return value" at src/single-dispatch-tests.jl:133
  0.014457 seconds
  0.010754 seconds
13:01:07 | DONE  (4/7) test item "Perf tests - mutable, no return value" <0.1 secs (53.7% compile), 126.21 K allocs (8.789 MB)
13:01:07 | START (5/7) test item "Perf tests - immutable, with return value" at src/single-dispatch-tests.jl:198
  0.053619 seconds (1.34 M allocations: 20.493 MiB, 7.37% gc time)
  0.011624 seconds (1000.00 k allocations: 15.259 MiB)
13:01:07 | DONE  (5/7) test item "Perf tests - immutable, with return value" 0.1 secs (38.8% compile, 2.9% GC), 2.47 M allocs (46.359 MB)
13:01:07 | START (6/7) test item "Perf tests - immutable, no return value" at src/single-dispatch-tests.jl:259
  0.013745 seconds
  0.016011 seconds (1000.00 k allocations: 15.259 MiB, 15.69% gc time)
13:01:07 | DONE  (6/7) test item "Perf tests - immutable, no return value" <0.1 secs (51.1% compile, 2.6% GC), 1.13 M allocs (24.847 MB)
```
