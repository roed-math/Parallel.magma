// Tests for TimeoutCall intrinsic

// Helper functions for testing
function fast_func(x)
  return x^2;
end function;

function slow_func(x)
  Sleep(10);
  return x^2;
end function;

function multi_return(x)
  return x, x + 1;
end function;

procedure do_nothing(x)
  _ := x;
end procedure;

// Test 1: Function completes within timeout
print "Test 1: Function completes within timeout";
success, output, elapsed := TimeoutCall(5, fast_func, <7>, 1);
assert success;
assert output[1] eq 49;
assert Type(elapsed) eq MonStgElt;  // elapsed is a time string
print "  PASSED";

// Test 2: Function times out
print "Test 2: Function times out";
success, output, elapsed := TimeoutCall(1, slow_func, <5>, 1 : Buffer:=0);
assert not success;
assert IsNone(output);
assert elapsed eq -1.0;  // -1.0 indicates timeout
print "  PASSED";

// Test 3: Multiple return values
print "Test 3: Multiple return values";
success, output, elapsed := TimeoutCall(5, multi_return, <10>, 2);
assert success;
assert output[1] eq 10;
assert output[2] eq 11;
print "  PASSED";

// Test 4: Zero results (procedure)
print "Test 4: Zero results";
success, output, elapsed := TimeoutCall(5, do_nothing, <42>, 0);
assert success;
assert #output eq 0;
print "  PASSED";

// Test 5: Custom buffer
print "Test 5: Custom buffer";
success, output, elapsed := TimeoutCall(2, fast_func, <3>, 1 : Buffer:=2);
assert success;
assert output[1] eq 9;
print "  PASSED";

// Test 6: HardKill on a fast call returns its result
print "Test 6: HardKill, fast call";
success, output, elapsed := TimeoutCall(5, fast_func, <6>, 1 : HardKill:=true);
assert success;
assert output[1] eq 36;
print "  PASSED";

// Test 7: HardKill bounds a call stuck in an uninterruptible C builtin, which the
// child's own Alarm cannot interrupt (ShortVectors runs for minutes here)
print "Test 7: HardKill, uninterruptible builtin";
function stuck_func(x)
  return #ShortVectors(Lattice("Lambda", 24), 12);
end function;
t0 := Realtime();
success, output, elapsed := TimeoutCall(1, stuck_func, <0>, 1 : Buffer:=0, HardKill:=true);
assert not success;
assert Realtime(t0) lt 15;   // watchdog deadline is timeout + 2*Buffer + 2 = 3s
print "  PASSED";

// Test 8: HardKill overhead.  The watchdog belongs to the compute child, so the parent
// does not wait for it; an earlier version cost ~140ms per call this way.
print "Test 8: HardKill overhead";
N := 20;
t0 := Realtime();
for i in [1..N] do
  success, output, elapsed := TimeoutCall(5, fast_func, <i>, 1 : HardKill:=true);
  assert success and output[1] eq i^2;
end for;
printf "  %o ms per HardKill call\n", Round(1000*Realtime(t0)/N);
print "  PASSED";

print "";
print "All tests passed!";
