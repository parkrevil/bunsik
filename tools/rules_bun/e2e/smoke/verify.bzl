"""소비자가 작성하는 룰. 공개 API 만 쓴다.

룰셋 내부(`//bun/private/...`)를 참조하지 않는다. 외부 모듈이 실제로
할 수 있는 것만으로 툴체인이 해석·다운로드·실행되는지 확인한다.
"""

load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

_WRITE_VERSION = "await Bun.write(Bun.argv[Bun.argv.length - 1], Bun.version + \"\\n\")"

def _impl(ctx):
    bun = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo.bun
    out = ctx.actions.declare_file(ctx.label.name + ".txt")

    args = ctx.actions.args()
    args.add("-e", _WRITE_VERSION)
    args.add(out)

    ctx.actions.run(
        executable = bun,
        arguments = [args],
        outputs = [out],
        tools = [bun],
        mnemonic = "BunVersion",
        progress_message = "Bun 버전 확인 중 %{label}",
    )
    return [DefaultInfo(files = depset([out]))]

verify_toolchain = rule(
    implementation = _impl,
    toolchains = [BUN_TOOLCHAIN_TYPE],
    doc = "공개 툴체인 타입만으로 Bun 을 실행할 수 있는지 확인한다.",
)
