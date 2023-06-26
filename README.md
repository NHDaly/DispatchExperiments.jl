# DispatchExperiments.jl

Implementation of polymorphic single dispatch via Virtual Tables (a la C++'s polymorphism) in Julia.

Mostly this was just for fun. This could maybe also be used for a baseline comparison of the performance of dynamic multiple dispatch in julia against a single dispatch case.

Here is the current state of the comparisons, per the tests.
Julia's dispatch is the first number, and the package's dispatch is the second number:
```julia
13:28:20 | START (3/7) test item "Perf tests - mutable, with return value" at src/single-dispatch-tests.jl:74
  0.044915 seconds (670.00 k allocations: 10.332 MiB, 11.10% gc time, 6.34% compilation time)
  0.009156 seconds
13:28:20 | DONE  (3/7) test item "Perf tests - mutable, with return value" 0.1 secs (44.0% compile, 4.0% GC), 794.28 K allocs (19.441 MB)
13:28:20 | START (4/7) test item "Perf tests - mutable, no return value" at src/single-dispatch-tests.jl:133
  0.014747 seconds
  0.010370 seconds
13:28:20 | DONE  (4/7) test item "Perf tests - mutable, no return value" <0.1 secs (52.9% compile), 130.89 K allocs (9.106 MB)
13:28:20 | START (5/7) test item "Perf tests - immutable, with return value" at src/single-dispatch-tests.jl:198
  0.064298 seconds (1.31 M allocations: 20.065 MiB, 6.27% gc time)
  0.008101 seconds
13:28:20 | DONE  (5/7) test item "Perf tests - immutable, with return value" 0.1 secs (36.1% compile, 2.8% GC), 1.45 M allocs (30.177 MB)
13:28:20 | START (6/7) test item "Perf tests - immutable, no return value" at src/single-dispatch-tests.jl:264
  0.015325 seconds
  0.010138 seconds
13:28:20 | DONE  (6/7) test item "Perf tests - immutable, no return value" <0.1 secs (53.9% compile), 132.69 K allocs (9.137 MB)
```
