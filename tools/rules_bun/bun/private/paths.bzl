"""경로 계산 헬퍼.

이 파일은 공식 체크리스트가 말하는 `<lang>/runfiles/` 라이브러리가
**아니다**. 그건 타겟 언어(여기서는 Bun) 프로그램이 실행 중에 runfiles 를
찾는 라이브러리이고, 아직 없다. 여기 있는 것은 Starlark 쪽 경로 계산이다.

`File.short_path` 는 외부 저장소의 파일에 대해 `../<repo>/<path>` 형태를 낸다.
runfiles 매니페스트의 실제 키는 거기서 `../` 만 벗긴 `<repo>/<path>` 다.

실측(Bazel 9.2.0, bzlmod):

    short_path            ../rules_bun++bun+bun_linux-x64/bun
    매니페스트 키          rules_bun++bun+bun_linux-x64/bun

`bazel-contrib/rules-template` 은 여기에 `external/` 을 덧붙이는데,
그 값은 execroot 상대 경로와 같아서 액션에서는 우연히 맞지만
runfiles 에서는 키가 어긋난다. 그대로 베끼지 않는다.
"""

def runfiles_path(ctx, file):
    """runfiles 루트 기준 상대 경로를 만든다.

    Args:
        ctx: 룰 컨텍스트.
        file: 대상 File.

    Returns:
        문자열.
    """
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    return ctx.workspace_name + "/" + file.short_path
