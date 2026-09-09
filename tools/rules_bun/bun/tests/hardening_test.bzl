"""하드닝 회귀 테스트.

`bun_action` 을 거친 액션의 작업 디렉터리에 공격용 `bunfig.toml` 과 `.env` 를
심어두고, 그것들이 실제로 무시되는지 산출물로 확인한다. 하드닝이 조용히
깨지면 이 테스트가 실패한다.
"""

load("//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")
load("//bun/private:hardening.bzl", "empty_bunfig", "hardening_args")
load("//bun/private:paths.bzl", "runfiles_path")

# preload 가 돌면 결과 문자열이 오염되고, .env 가 읽히면 PORT 가 채워진다.
_PROBE = """
const out = Bun.argv[Bun.argv.length - 1];
await Bun.write(out, JSON.stringify({
  poisoned: globalThis.__POISONED__ === true,
  port: process.env.PORT ?? null,
}) + "\\n");
"""

_ATTACK_PRELOAD = "globalThis.__POISONED__ = true;\n"
_ATTACK_BUNFIG = 'preload = ["./attack_preload.ts"]\n'
_ATTACK_ENV = "PORT=9999\n"

def _impl(ctx):
    # 액션 cwd(execroot)에서 보이도록 소스 옆에 공격 파일을 생성한다.
    preload = ctx.actions.declare_file("attack_preload.ts")
    bunfig = ctx.actions.declare_file("bunfig.toml")
    dotenv = ctx.actions.declare_file(".env")
    ctx.actions.write(preload, _ATTACK_PRELOAD)
    ctx.actions.write(bunfig, _ATTACK_BUNFIG)
    ctx.actions.write(dotenv, _ATTACK_ENV)

    out = ctx.actions.declare_file(ctx.label.name + ".json")

    # 공격은 "액션의 cwd 에 bunfig.toml/.env 가 있을 때" 성립한다.
    # ctx.actions.run 에는 cwd 인자가 없으므로 이 테스트에 한해 run_shell 로
    # 공격 파일이 있는 디렉터리로 이동한 뒤 bun 을 부른다.
    # (일반 룰은 bun_action 을 쓴다 — 여기만 예외다.)
    toolchain = ctx.toolchains[BUN_TOOLCHAIN_TYPE]
    bun = toolchain.buninfo.bun
    empty = empty_bunfig(ctx)

    hardening = " ".join([
        "'" + a + "'"
        for a in hardening_args(empty, relative_to = bunfig.dirname)
    ])

    ctx.actions.run_shell(
        inputs = [preload, bunfig, dotenv, empty],
        outputs = [out],
        tools = [bun],
        command = (
            'BUN="$(pwd)/{bun}"; OUT="$(pwd)/{out}"; ' +
            'cd "{dir}" && exec "$BUN" {hard} -e "$1" "$OUT"'
        ).format(
            bun = bun.path,
            out = out.path,
            dir = bunfig.dirname,
            hard = hardening,
        ),
        arguments = [_PROBE],
        mnemonic = "BunHardeningProbe",
    )

    # 산출물을 검사하는 테스트 스크립트.
    checker = ctx.actions.declare_file(ctx.label.name + ".check.js")
    ctx.actions.write(checker, """
const r = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
const fail = [];
if (r.poisoned) fail.push("bunfig.toml 의 preload 가 실행됐다");
if (r.port !== null) fail.push(".env 가 읽혔다 (PORT=" + r.port + ")");
if (fail.length) { console.error("하드닝 실패:\\n  " + fail.join("\\n  ")); process.exit(1); }
console.log("하드닝 정상: preload 차단, .env 차단");
""")

    bun = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo.bun
    launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        launcher,
        # RUNFILES_DIR / TEST_SRCDIR 은 Bazel 이 테스트에 제공하는 계약이다
        # (bazel-rule-authoring.md §7.3). $0 기반 경로 추정보다 안전하다.
        '#!/bin/sh\nR="${{RUNFILES_DIR:-$TEST_SRCDIR}}"\nexec "$R/{bun}" "$R/{chk}" "$R/{out}"\n'.format(
            bun = runfiles_path(ctx, bun),
            chk = runfiles_path(ctx, checker),
            out = runfiles_path(ctx, out),
        ),
        is_executable = True,
    )
    return [DefaultInfo(
        executable = launcher,
        runfiles = ctx.runfiles(files = [
            out,
            checker,
            bun,
        ]),
    )]

hardening_test = rule(
    implementation = _impl,
    test = True,
    toolchains = [BUN_TOOLCHAIN_TYPE],
    doc = "cwd 의 bunfig.toml/.env 가 무시되는지 확인한다.",
)
