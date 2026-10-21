freeze;

intrinsic TimeoutCall(timeout::RngIntElt, f::Program, input::Tup, number_of_results::RngIntElt : Parameters:=[], Buffer:=1, HardKill:=false) -> BoolElt, List, Any
  { Call f on the input with a timeout in seconds. Returns success, output, elapsed time.
    The compute runs in a forked child that arms its own Alarm(timeout+Buffer); that
    interrupts anything which yields to the interpreter.  Set HardKill for calls that may
    enter an uninterruptible C-level builtin (a tight loop that never returns to the
    interpreter, so the Alarm's SIGALRM is never serviced -- e.g. a pathological
    AdjacencyMatrix or GenusRepresentatives): a watchdog process then SIGKILLs the compute
    child once it overruns the deadline.  The watchdog is a detached shell the compute
    child starts for itself, so the parent never waits on it: HardKill costs a few
    milliseconds per call (one shell spawn), cheap enough for per-lattice calls. }
  require timeout ge 1 : "Argument 1 must be at least 1";
  require number_of_results ge 0 : "Argument 4 must be non-negative";
  require Buffer ge 0 : "Buffer must be non-negative";

  outfile, F := TemporaryFile();
  delete F;  // close handle, we'll write from child

  child := _Fork(:CloseStdin:=true);
  if child eq 0 then
    // Compute child.  Its own Alarm interrupts anything that yields to the interpreter.
    if HardKill then
      // The Alarm below cannot interrupt an uninterruptible builtin, and the parent's
      // WaitForAllChildren() would then block forever.  So start a detached watchdog
      // shell that SIGKILLs this process once it overruns the deadline.  It belongs to
      // this child, not to the parent, so the parent waits only for the computation
      // (an earlier version forked the watchdog from the parent, which then also waited
      // for its 0.2s poll to notice the child had exited: ~140ms per call against ~3ms
      // without HardKill).  It polls at leisure and exits once this process is gone;
      // before killing it checks the process start time, so a recycled PID is never
      // hit.  `ps -o lstart=` rather than /proc so it also works on macOS.
      deadline := timeout + 2*Buffer + 2;
      _ := System(Sprintf("(p=%o; s=\"$(ps -o lstart= -p $p)\"; i=0; while [ $i -lt %o ]; do kill -0 $p 2>/dev/null || exit 0; sleep 0.2; i=$((i+1)); done; [ \"$(ps -o lstart= -p $p)\" = \"$s\" ] && kill -9 $p) </dev/null >/dev/null 2>&1 &", Getpid(), 5*deadline));
    end if;
    Alarm(timeout + Buffer);
    start := Time();
    success, output := Call(f, input, number_of_results : Parameters:=Parameters);
    elapsed := Time(start);
    WriteObject(Open(outfile, "w"), <success, EncodeNone(output), elapsed>);
    exit 0;
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
