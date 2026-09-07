"""툴체인 타겟만 담는 별칭 저장소를 만든다.

공식 지침(Deploying rules)에 따른 분리다. Bazel 은 등록된 모든 툴체인 타겟을
분석 단계에서 봐야 하지만, `toolchain.toolchain` 속성이 가리키는 대상까지
분석하지는 않는다. 그래서 무거운 다운로드(플랫폼별 Bun 바이너리)는
플랫폼별 저장소에 두고, 여기에는 가벼운 별칭만 둔다.
"""

load(":platforms.bzl", "PLATFORMS")

def _toolchains_repo_impl(repository_ctx):
    build_content = """# bun/private/toolchains_repo.bzl 가 생성함
# MODULE.bazel 의 register_toolchains 또는 --extra_toolchains 로 등록된다.
"""

    for platform, meta in PLATFORMS.items():
        build_content += """
toolchain(
    name = "{platform}_toolchain",
    # Bun 은 빌드 도구다. 실행되는 곳(exec)만 제약하고 target 은 제약하지 않는다.
    # 양쪽에 같은 제약을 걸면 exec == target 인 조합만 성립해 크로스 컴파일이
    # 원천 불가해진다(재현: --platforms 를 바꾸면 "No matching toolchains").
    exec_compatible_with = {compatible_with},
    toolchain = "@{user_repo}_{platform}//:bun_toolchain",
    toolchain_type = "@rules_bun//bun:toolchain_type",
)
""".format(
            platform = platform,
            user_repo = repository_ctx.attr.user_repository_name,
            compatible_with = meta.compatible_with,
        )

    repository_ctx.file("BUILD.bazel", build_content)

    # Bazel 8.3.0 미만에는 repo_metadata 가 없다.
    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = True)

toolchains_repo = repository_rule(
    _toolchains_repo_impl,
    doc = "플랫폼별 툴체인 별칭만 담는 저장소.",
    attrs = {
        "user_repository_name": attr.string(
            mandatory = True,
            doc = "플랫폼별 저장소 이름의 접두사.",
        ),
    },
)
