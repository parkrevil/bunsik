"""Bun 액션을 만드는 공용 헬퍼.

룰은 `ctx.actions.run` 을 직접 부르지 않고 반드시 이 함수를 쓴다.
그래야 하드닝이 한 곳에서 강제되고, 새 룰에서 빠뜨릴 수 없다.
"""

load(":hardening.bzl", "empty_bunfig", "hardening_args")

def bun_action(
        ctx,
        arguments,
        outputs,
        inputs = [],
        mnemonic = "BunAction",
        progress_message = None,
        env = {}):
    """하드닝이 적용된 Bun 액션을 등록한다.

    Args:
        ctx: 룰 컨텍스트.
        arguments: bun 에 넘길 인자. 문자열 또는 File 의 리스트.
        outputs: 이 액션이 만드는 File 리스트.
        inputs: 추가 입력 File 또는 depset.
        mnemonic: 액션 니모닉.
        progress_message: 진행 메시지. 생략하면 니모닉을 쓴다.
        env: 추가 환경변수. 기본 환경은 비어 있다.
    """
    toolchain = ctx.toolchains["//bun/toolchain:type"]
    bun = toolchain.buninfo.bun
    bunfig = empty_bunfig(ctx)

    args = ctx.actions.args()
    args.add_all(hardening_args(ctx, bunfig))
    args.add_all(arguments)

    direct = [bunfig]
    transitive = []
    for i in inputs if type(inputs) == "list" else [inputs]:
        if type(i) == "depset":
            transitive.append(i)
        else:
            direct.append(i)

    ctx.actions.run(
        executable = bun,
        arguments = [args],
        inputs = depset(direct, transitive = transitive),
        outputs = outputs,
        tools = [bun],
        # 호스트 환경을 물려받지 않는다. 필요한 것만 명시한다.
        env = env,
        mnemonic = mnemonic,
        progress_message = progress_message or (mnemonic + " %{label}"),
    )
