"""툴체인 해석·다운로드·실행을 한 번에 검증하는 최소 룰."""

load("//bun/private:action.bzl", "bun_action")

# POSIX 셸에 의존하지 않도록 Bun 이 직접 파일을 쓰게 한다.
_WRITE_VERSION = "await Bun.write(Bun.argv[Bun.argv.length - 1], Bun.version + \"\\n\")"

def _bun_version_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    bun_action(
        ctx,
        arguments = ["-e", _WRITE_VERSION, out],
        outputs = [out],
        mnemonic = "BunVersion",
    )
    return [DefaultInfo(files = depset([out]))]

bun_version = rule(
    implementation = _bun_version_impl,
    toolchains = ["//bun/toolchain:type"],
    doc = "툴체인의 Bun 버전을 파일로 남긴다.",
)
