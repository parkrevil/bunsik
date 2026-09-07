"""runfiles 키 계산.

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
