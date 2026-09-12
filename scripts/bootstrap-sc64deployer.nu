use common.nu *
const REVISION = 'a1e7996d2cbece686820a5c785029c68514f17b0'
def main [] {
    let source = $ROOT | path join .build summercart64-src
    let output = $ROOT | path join .build bin sc64deployer
    if ($output | path exists) { print $'sc64deployer is already installed at ($output)'; return }
    mkdir ($output | path dirname)
    if not ($source | path join .git | path exists) { command git [clone https://github.com/Polprzewodnikowy/SummerCart64.git $source] }
    command git [-C $source fetch origin $REVISION]
    command git [-C $source checkout --detach $REVISION]
    command cargo [build --locked --release --manifest-path ($source | path join sw deployer Cargo.toml)]
    cp ($source | path join sw deployer target release sc64deployer) $output
}
