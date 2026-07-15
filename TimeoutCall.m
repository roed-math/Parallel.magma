freeze;

intrinsic TimeoutCall(timeout::RngIntElt, f::Program, input::Tup, number_of_results::RngIntElt : Parameters:=[], Buffer:=1, HardKill:=false) -> BoolElt, List, Any
  { Call f on the input with a timeout in seconds. Returns success, output, elapsed time.
    The compute runs in a forked child that arms its own Alarm(timeout+Buffer); that
    interrupts anything which yields to the interpreter.  Set HardKill for calls that may
    enter an uninterruptible C-level builtin (a tight loop that never returns to the
    interpreter, so the Alarm's SIGALRM is never serviced -- e.g. a pathological
    AdjacencyMatrix or GenusRepresentatives): a watchdog process then SIGKILLs the compute
    child once it overruns the deadline.  HardKill adds up to a ~0.2s latency floor, so
    enable it only for the few genus-level calls, not the many fast per-lattice ones. }
  require timeout ge 1 : "Argument 1 must be at least 1";
  require number_of_results ge 0 : "Argument 4 must be non-negative";
  require Buffer ge 0 : "Buffer must be non-negative";

  outfile, F := TemporaryFile();
  delete F;  // close handle, we'll write from child

  child := _Fork(:CloseStdin:=true);
  if child eq 0 then
    // Compute child.  Its own Alarm interrupts anything that yields to the interpreter.
    Alarm(timeout + Buffer);
    start := Time();
    success, output := Call(f, input, number_of_results : Parameters:=Parameters);
    elapsed := Time(start);
    WriteObject(Open(outfile, "w"), <success, EncodeNone(output), elapsed>);
    exit 0;
  end if;

  if HardKill then
    // WaitForAllChildren() below blocks indefinitely, and the compute child's Alarm
    // cannot interrupt an uninterruptible builtin -- so without this the whole process
    // hangs.  (Alarm is a SIGALRM that is uncatchable in Magma, so the parent cannot
    // simply time its own wait; hence a separate watchdog process.)  The watchdog polls
    // and SIGKILLs the compute child once it overruns the deadline, but exits as soon as
    // the compute child is gone, so a fast call is delayed by at most one poll interval.
    deadline := timeout + 2*Buffer + 2;
    watchdog := _Fork(:CloseStdin:=true);
    if watchdog eq 0 then
      _ := System(Sprintf("i=0; while [ $i -lt %o ]; do kill -0 %o 2>/dev/null || exit 0; sleep 0.2; i=$((i+1)); done; kill -9 %o 2>/dev/null", 5*deadline, child, child));
      exit 0;
    end if;
  end if;

  // Parent process
  WaitForAllChildren();

  // Check if output file has content (child completed before timeout)
  if #Read(outfile) gt 0 then
    success, output, elapsed := Explode(ReadObject(Open(outfile, "r")));
    Remove(outfile);
    return success, DecodeNone(output), elapsed;
  else
    // Timeout or crash - empty output file
    Remove(outfile);
    return false, None, -1.0;
  end if;
end intrinsic;
