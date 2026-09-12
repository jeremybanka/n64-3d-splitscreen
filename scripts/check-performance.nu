# Check sustained one-second samples from `just build --benchmark 1`.
use common.nu [fail]
def main [log: path, --minimum: int = 40, --samples-per-phase: int = 15] {
    if $minimum < 1 or $samples_per_phase < 1 { fail 'Minimum FPS and samples per phase must be positive' }
    let text = open --raw $log
    if $text =~ 'RDPQ_VALIDATION|ASSERTION|capacity exceeded' { fail 'FAIL: diagnostic errors in the capture' }
    let rows = $text | parse --regex 'PERF views=(?<views>\d+) phase=(?<phase>\d+) fps=(?<fps>\d+) cpu_us=(?<cpu>\d+) submit_us=(?<submit>\d+) triangles=(?<triangles>\d+)' | update views { into int } | update phase { into int } | update fps { into int }
    if ($rows | is-empty) or ($rows | any {|row| $row.views != 4 }) { fail 'FAIL: capture must contain only four-player samples' }
    for phase in ([tour 'independent movement' 'close quarters'] | enumerate) {
        let samples = $rows | where phase == $phase.index | get fps
        if ($samples | length) < $samples_per_phase { fail $'FAIL: phase ($phase.index) needs ($samples_per_phase) complete samples' }
        print $'($phase.item): ($samples | length) samples; ($samples | math min)–($samples | math max) FPS; mean ($samples | math avg | math round --precision 1)'
        if ($samples | math min) < $minimum { fail $'FAIL: phase ($phase.index) fell below ($minimum) FPS' }
    }
    print $'PASS: all ($rows | length) one-second samples reached ($minimum)+ FPS'
}
