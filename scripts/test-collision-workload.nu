use std/assert
use collision-workload.nu check-collision-workload

def main [] {
    for option in [{mode: off, value: 0} {mode: on, value: 1}] {
        let capture = $"PERF collision=($option.value)\nPERF collision=($option.value)"
        assert str contains (check-collision-workload $capture $option.mode) $option.mode
    }
    for invalid in ["PERF collision=0\nPERF collision=1" "PERF collision=0\nPERF fps=60" 'PERF collision=2' ''] {
        assert error { check-collision-workload $invalid }
    }
    assert error { check-collision-workload 'PERF fps=60' }
    assert str contains (check-collision-workload 'PERF fps=60' legacy) 'Historical'
    assert error { check-collision-workload 'PERF collision=0' legacy }
    print 'Collision workload: explicit modes, mixed/missing tags and historical selection pass'
}
