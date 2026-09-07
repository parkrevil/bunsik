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
        env = {},
        param_file = False):
    """하드닝이 적용된 Bun 액션을 등록한다.

    Args:
        ctx: 룰 컨텍스트.
        arguments: bun 에 넘길 인자. 문자열·File·depset 의 리스트.
        outputs: 이 액션이 만드는 File 리스트.
        inputs: 추가 입력 File 또는 depset.
        mnemonic: 액션 니모닉.
        progress_message: 진행 메시지. 생략하면 니모닉을 쓴다.
        env: 추가 환경변수. 기본 환경은 비어 있다.
        param_file: 인자를 param file 로 넘길지 여부. **기본값 False 다.**

            `bun` 자체는 `@file` 을 확장하지 않는다(실측: `bun s.ts @args.txt`
            → argv 에 `"@args.txt"` 가 그대로 남고, `bun build @args.txt` 는
            `ModuleNotFound` 로 실패한다). 그래서 무조건 켤 수 없다.

            인자가 수천 개가 되는 액션은 **직접 작성한 Bun 스크립트**를
            실행하고, 그 스크립트가 `@file` 을 읽도록 만든 뒤 여기서
            `param_file = True` 를 준다. 문자열 이어붙이기(O(N^2))를 피하기
            위한 수단이며, 지금은 그런 룰이 없어 쓰이지 않는다.
    """
    toolchain = ctx.toolchains["//bun:toolchain_type"]
    bun = toolchain.buninfo.bun
    bunfig = empty_bunfig(ctx)

    # 하드닝 인자는 bun 이 직접 해석해야 하므로 param file 에 넣지 않는다.
    hardening = ctx.actions.args()
    hardening.add_all(hardening_args(bunfig))

    payload = ctx.actions.args()
    payload.add_all(arguments)
    if param_file:
        payload.use_param_file("@%s", use_always = True)
        payload.set_param_file_format("multiline")

    direct = [bunfig]
    transitive = []
    for i in inputs if type(inputs) == "list" else [inputs]:
        if type(i) == "depset":
            transitive.append(i)
        else:
            direct.append(i)

    ctx.actions.run(
        executable = bun,
        arguments = [hardening, payload],
        inputs = depset(direct, transitive = transitive),
        outputs = outputs,
        tools = [bun],
        # 호스트 환경을 물려받지 않는다. 필요한 것만 명시한다.
        env = env,
        mnemonic = mnemonic,
        progress_message = progress_message or (mnemonic + " %{label}"),
    )
