"""`bun_action` 이 하드닝을 실제로 방출하는지 분석 단계에서 검증한다.

행위 테스트(`hardening_test`)는 "이 플래그들이 공격을 막는다"를 증명한다.
이 테스트는 "모든 룰이 그 플래그를 실제로 달고 나간다"를 증명한다.
둘 다 있어야 계약이 지켜진다 — 행위 테스트만 있으면 `bun_action` 을
우회하거나 거기서 하드닝을 빼도 아무도 모른다.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//bun/private:action.bzl", "bun_action")

# --- 검사 대상: bun_action 을 쓰는 최소 룰 -----------------------------------

def _fixture_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".txt")
    bun_action(
        ctx,
        arguments = ["-e", "await Bun.write(Bun.argv[Bun.argv.length - 1], \"ok\\n\")", out],
        outputs = [out],
        mnemonic = "BunFixture",
    )
    return [DefaultInfo(files = depset([out]))]

action_fixture = rule(
    implementation = _fixture_impl,
    toolchains = ["//bun:toolchain_type"],
    doc = "bun_action 을 통과하는 최소 룰. 테스트 전용.",
)

# --- analysistest ------------------------------------------------------------

_REQUIRED = [
    "--no-install",
    "--no-env-file",
]

def _hardening_emitted_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [a for a in analysistest.target_actions(env) if a.mnemonic == "BunFixture"]
    asserts.equals(env, 1, len(actions), "BunFixture 액션이 정확히 하나여야 한다")

    argv = actions[0].argv
    for flag in _REQUIRED:
        asserts.true(
            env,
            flag in argv,
            "bun_action 이 {} 를 방출하지 않았다. argv={}".format(flag, argv),
        )

    asserts.true(
        env,
        [a for a in argv if a.startswith("--config=")],
        "bun_action 이 --config=<빈 bunfig> 를 방출하지 않았다. argv={}".format(argv),
    )
    return analysistest.end(env)

hardening_emitted_test = analysistest.make(_hardening_emitted_test_impl)
