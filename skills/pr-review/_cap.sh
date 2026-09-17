# cap <seconds> <command...> — run a command with a hard time limit.
#
# A plain `alarm` only kills the wrapper: children keep the pipe open and the caller's
# command substitution waits forever. This runs the command in its own process group and
# kills the group, so `pnpm` and friends die with it. Exit 124 on timeout.
cap() {
  local t="$1"; shift
  perl -e '
    my $t = shift;
    my $pid = fork();
    if (!defined $pid) { exit 125 }
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV; exit 127 }
    $SIG{ALRM} = sub { kill("KILL", -$pid); waitpid($pid, 0); exit 124 };
    alarm $t;
    waitpid($pid, 0);
    alarm 0;
    exit($? >> 8);
  ' "$t" "$@" 2>&1
}
