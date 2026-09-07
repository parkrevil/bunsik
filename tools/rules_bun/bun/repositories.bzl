"""Bun 실행 파일을 플랫폼별로 내려받는 저장소 룰.

무결성 검증은 선택이 아니다. `integrity` 없이 원격 바이너리를 가져오면
재현 불가능한 빌드와 공급망 변조에 그대로 노출된다.
"""

load("//bun/private:platforms.bzl", "PLATFORMS")
load("//bun/private:toolchains_repo.bzl", "toolchains_repo")
load("//bun/private:versions.bzl", "TOOL_VERSIONS")

_DOC = "Bun 툴체인에 필요한 외부 도구를 가져온다."

_ATTRS = {
    "bun_version": attr.string(mandatory = True, values = TOOL_VERSIONS.keys()),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
}

def _bun_repo_impl(repository_ctx):
    platform = repository_ctx.attr.platform
    version = repository_ctx.attr.bun_version

    url = "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}.zip".format(
        version = version,
        platform = platform,
    )

    # 아카이브는 `bun-<platform>/bun` 형태다(직접 확인). 접두사를 벗겨
    # 저장소 루트에 실행 파일이 놓이게 한다.
    repository_ctx.download_and_extract(
        url = url,
        integrity = TOOL_VERSIONS[version][platform],
        stripPrefix = "bun-" + platform,
    )

    exe = ".exe" if platform.startswith("windows") else ""

    repository_ctx.file("BUILD.bazel", """# bun/repositories.bzl 가 생성함
load("@rules_bun//bun:toolchain.bzl", "bun_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["bun{exe}"])

bun_toolchain(
    name = "bun_toolchain",
    bun = "bun{exe}",
    version = "{version}",
)
""".format(exe = exe, version = version))

    if not hasattr(repository_ctx, "repo_metadata"):
        return None
    return repository_ctx.repo_metadata(reproducible = True)

bun_repositories = repository_rule(
    _bun_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

def bun_register_toolchains(name, **kwargs):
    """플랫폼별 저장소와 툴체인 별칭 저장소를 만든다.

    Args:
        name: 생성될 저장소 이름의 접두사.
        **kwargs: 각 `bun_repositories` 호출에 전달된다.
    """
    for platform in PLATFORMS.keys():
        bun_repositories(
            name = name + "_" + platform,
            platform = platform,
            **kwargs
        )

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
