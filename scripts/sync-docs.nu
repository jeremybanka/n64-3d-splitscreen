use common.nu *
def main [] {
    let docs = $ROOT | path join docs
    for name in [zig libdragon summercart64 m64] { mkdir ($docs | path join $name) }
    with-temp docs-refresh {|scratch|
        http get --raw https://ziglang.org/documentation/0.16.0/ | save --force ($docs | path join zig language-reference-0.16.0.html)
        command git [clone --depth 1 --branch trunk https://github.com/DragonMinded/libdragon.git ($scratch | path join libdragon)]
        command git [clone --depth 1 https://github.com/DragonMinded/libdragon.wiki.git ($scratch | path join libdragon-wiki)]
        command git [clone --depth 1 https://github.com/Polprzewodnikowy/SummerCart64.git ($scratch | path join summercart64)]
        rm --recursive --force ($docs | path join libdragon wiki) ($docs | path join libdragon headers)
        cp --recursive ($scratch | path join libdragon-wiki) ($docs | path join libdragon wiki)
        rm --recursive --force ($docs | path join libdragon wiki .git)
        cp --recursive ($scratch | path join libdragon include) ($docs | path join libdragon headers)
        cp ($scratch | path join libdragon README.md) ($docs | path join libdragon README.upstream.md)
        cp ($scratch | path join libdragon LICENSE.md) ($docs | path join libdragon LICENSE.md)
        capture git [-C ($scratch | path join libdragon) rev-parse HEAD] | save --force ($docs | path join libdragon REVISION)
        rm --recursive --force ($docs | path join summercart64 protocol)
        cp --recursive ($scratch | path join summercart64 docs) ($docs | path join summercart64 protocol)
        cp ($scratch | path join summercart64 README.md) ($docs | path join summercart64 README.upstream.md)
        let license = $scratch | path join summercart64 LICENSE
        if ($license | path exists) { cp $license ($docs | path join summercart64 LICENSE) }
        capture git [-C ($scratch | path join summercart64) rev-parse HEAD] | save --force ($docs | path join summercart64 REVISION)
        http get --raw https://support.modretro.com/en_us/m64-manual-r1tovFQgMg | save --force ($docs | path join m64 manual.snapshot.html)
    }
    print $'Documentation snapshots refreshed in ($docs)'
}
