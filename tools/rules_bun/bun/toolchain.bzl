"""Bun 툴체인 룰.

툴체인 해석은 빌트인 `platform_common.ToolchainInfo` 만 인정한다.
동명의 커스텀 provider 를 선언하면 그것이 빌트인을 가려서
"does not provide ToolchainInfo" 로 해석이 실패한다.
"""

BunInfo = provider(
    doc = "Bun 실행 파일을 호출하는 방법.",
    fields = {
        "bun": "Bun 실행 파일 File. 액션에서는 `executable`/`tools` 로 넘긴다.",
        "version": "Bun 버전 문자열. 분석 단계에서 버전별 분기에 쓴다.",
        "tool_files": "runfiles 에 넣어야 하는 파일들.",
    },
)

def _bun_toolchain_impl(ctx):
    bun = ctx.file.bun
    tool_files = [bun]

    default = DefaultInfo(
        files = depset(tool_files),
        runfiles = ctx.runfiles(files = tool_files),
    )

    return [
        default,
        platform_common.ToolchainInfo(
            buninfo = BunInfo(
                bun = bun,
                version = ctx.attr.version,
                tool_files = tool_files,
            ),
        ),
    ]

bun_toolchain = rule(
    implementation = _bun_toolchain_impl,
    attrs = {
        "bun": attr.label(
            doc = "hermetic 하게 내려받은 Bun 실행 파일.",
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(
            doc = "이 툴체인이 제공하는 Bun 버전.",
            mandatory = True,
        ),
    },
    doc = "Bun 툴체인을 정의한다.",
)
