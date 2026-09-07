"""모든 Bun 액션에 공통으로 붙는 인자와 환경.

목적은 **재현 가능한 빌드**다. 같은 입력이면 언제 어디서 돌려도 같은 출력이
나와야 하는데, Bun 은 기본적으로 실행 시점의 주변 상태를 읽어 그걸 깬다.

실측(Bun 1.4.2)으로 확인한 것과 대응:

  bun <파일>              node_modules 에 없는 패키지를 npm 에서 자동 설치한다.
                          빌드가 네트워크를 타면 재현성이 사라진다.
                          → --no-install

  cwd 의 bunfig.toml      preload 가 액션 안에서 실행된다. 이 파일은 액션의
                          선언된 입력이 아니라 action key 에 안 들어가므로,
                          바뀐 산출물이 "정상" 키로 캐시에 남는다.
                          → --config=<빈 파일>

  cwd 의 .env             process.env 에 값이 주입된다.
                          → --no-env-file

확인했으나 대응이 불필요한 것:

  ~/.bunfig.toml          읽지 않는다. cwd 것만 읽는다.
  NODE_OPTIONS            Bun 이 무시한다.
  HOME / PATH             Bazel 액션 환경에 애초에 없다(use_default_shell_env
                          기본값이 False). 샌드박스에서는 소스 자체가 안 보인다.
                          위 셋이 실제로 문제가 되는 건 --spawn_strategy=local
                          같은 비샌드박스 실행이다.

`/dev/null` 은 쓰지 않는다. Windows 에 없는 경로이고, Bun 은 없는 설정 파일에
하드 실패한다(`ENOENT ... while reading config`). 빈 파일을 액션 입력으로
선언해 넘긴다.
"""

# 설정 파일 경로가 필요 없는 인자들.
_BASE_ARGS = [
    "--no-install",
    "--no-env-file",
]

def empty_bunfig(ctx):
    """액션에 넘길 빈 bunfig.toml 을 만든다.

    Args:
        ctx: 룰 컨텍스트.

    Returns:
        선언된 입력으로 넣어야 하는 File.
    """
    f = ctx.actions.declare_file(ctx.label.name + ".empty.bunfig.toml")
    ctx.actions.write(f, "")
    return f

def hardening_args(bunfig, relative_to = None):
    """`ctx.actions.args()` 에 넣을 하드닝 인자 목록.

    Args:
        bunfig: `empty_bunfig()` 가 만든 File.
        relative_to: 액션이 cwd 를 옮기는 경우 그 디렉터리. 설정 파일 경로를
            거기서부터의 상대 경로로 만든다. 보통은 None.

    Returns:
        문자열 리스트.
    """
    path = bunfig.path
    if relative_to:
        depth = len(relative_to.split("/"))
        path = "/".join([".."] * depth) + "/" + path
    return _BASE_ARGS + ["--config=" + path]
