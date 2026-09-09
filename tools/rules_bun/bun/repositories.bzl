"""Bun 실행 파일을 플랫폼별로 내려받는 저장소 룰.

무결성 검증은 선택이 아니다. `integrity` 없이 원격 바이너리를 가져오면
재현 불가능한 빌드와 공급망 변조에 그대로 노출된다.
"""

load("//bun/private:platforms.bzl", "PLATFORMS")
load("//bun/private:toolchains_repo.bzl", "toolchains_repo")
load("//bun/private:versions.bzl", "TOOL_VERSIONS")

_DOC = "Bun 툴체인에 필요한 외부 도구를 가져온다."

_ATTRS = {
    "bun_version": attr.string(mandatory = True),
    "integrity": attr.string(
        doc = "이 플랫폼 아카이브의 integrity. 비우면 versions.bzl 에서 찾는다.",
    ),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
}

def _bun_repo_impl(repository_ctx):
    platform = repository_ctx.attr.platform
    version = repository_ctx.attr.bun_version

    url = "https://github.com/oven-sh/bun/releases/download/bun-v{version}/bun-{platform}.zip".format(
        version = version,
        platform = platform,
    )

    # 룰셋이 아는 버전이면 여기서 integrity 를 찾고, 모르는 버전이면
    # 소비자가 직접 넘겨야 한다. 무결성 검증을 건너뛰는 경로는 없다.
    integrity = repository_ctx.attr.integrity
    if not integrity:
        if version not in TOOL_VERSIONS:
            fail((
                "rules_bun 이 Bun {version} 의 integrity 를 모른다. " +
                "MODULE.bazel 에서 직접 넘겨라:\n\n" +
                "    bun.toolchain(\n" +
                "        bun_version = \"{version}\",\n" +
                "        integrity = {{\n" +
                "            \"{platform}\": \"sha256-...\",\n" +
                "            # ... 사용할 플랫폼 전부\n" +
                "        }},\n" +
                "    )\n\n" +
                "값은 릴리스의 공식 SHASUMS256.txt 에서 얻는다:\n" +
                "    curl -sL https://github.com/oven-sh/bun/releases/download/" +
                "bun-v{version}/SHASUMS256.txt \\\n" +
                "      | grep '  bun-{platform}.zip$' | awk '{{print $1}}' \\\n" +
                "      | xxd -r -p | base64 -w0 | sed 's/^/sha256-/'"
            ).format(version = version, platform = platform))
        integrity = TOOL_VERSIONS[version][platform]

    # 아카이브는 `bun-<platform>/bun` 형태다(직접 확인). 접두사를 벗겨
    # 저장소 루트에 실행 파일이 놓이게 한다.
    repository_ctx.download_and_extract(
        url = url,
        integrity = integrity,
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

def bun_register_toolchains(name, integrity = {}, **kwargs):
    """플랫폼별 저장소와 툴체인 별칭 저장소를 만든다.

    Args:
        name: 생성될 저장소 이름의 접두사.
        integrity: 플랫폼 -> integrity 문자열. 룰셋이 모르는 Bun 버전을
            쓸 때 소비자가 넘긴다.
        **kwargs: 각 `bun_repositories` 호출에 전달된다.
    """
    for platform in PLATFORMS.keys():
        bun_repositories(
            name = name + "_" + platform,
            platform = platform,
            integrity = integrity.get(platform, ""),
            **kwargs
        )

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )
