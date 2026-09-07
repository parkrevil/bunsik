"""대상을 특정 플랫폼으로 전이시켜 빌드하게 하는 테스트 헬퍼.

크로스 컴파일 회귀를 자동으로 잡기 위한 것이다. `build_test` 는
`--platforms` 를 걸 수 없어 호스트에서만 빌드하므로, 명령행 옵션을
transition 으로 고정한다 (bazel-rule-authoring.md §6.2).
"""

def _transition_impl(_settings, attr):
    return {"//command_line_option:platforms": str(attr.platform)}

_platform_transition = transition(
    implementation = _transition_impl,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    return [DefaultInfo(
        files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.target]),
    )]

with_platform = rule(
    implementation = _impl,
    attrs = {
        "platform": attr.label(
            mandatory = True,
            doc = "이 플랫폼을 타겟 플랫폼으로 고정한다.",
        ),
        "target": attr.label_list(
            mandatory = True,
            cfg = _platform_transition,
            doc = "전이 후 빌드할 대상.",
        ),
    },
    doc = "대상을 지정한 플랫폼으로 빌드한다. 테스트 전용.",
)
