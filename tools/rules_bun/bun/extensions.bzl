"""bzlmod module extension — Bun 툴체인을 설치한다.

모든 모듈이 기본 이름("bun") 아래 버전을 선언할 수 있고, 그중 최신이 선택된다.
루트 모듈만 다른 이름으로 추가 툴체인을 선언할 수 있다.
"""

load("//bun:repositories.bzl", "bun_register_toolchains")

_DEFAULT_NAME = "bun"

bun_toolchain = tag_class(attrs = {
    "name": attr.string(
        doc = "생성될 저장소 이름의 기준. 기본값 변경은 루트 모듈만 허용된다.",
        default = _DEFAULT_NAME,
    ),
    "bun_version": attr.string(doc = "사용할 Bun 버전.", mandatory = True),
})

def _version_key(version):
    """정렬용 키. 문자열 정렬은 "1.10.0" 을 "1.4.2" 보다 작게 보므로 쓸 수 없다."""
    parts = []
    for piece in version.split("."):
        digits = ""
        for ch in piece.elems():
            if ch.isdigit():
                digits += ch
            else:
                break
        parts.append(int(digits) if digits else 0)

    # 자리수를 맞춰 비교 가능하게 한다(major, minor, patch).
    for _ in range(3 - len(parts)):
        parts.append(0)
    return parts[:3]

def _max_version(versions):
    """semver 기준 최댓값. Starlark 에는 정렬 키 인자가 없어 직접 비교한다."""
    best = versions[0]
    best_key = _version_key(best)
    for candidate in versions[1:]:
        key = _version_key(candidate)
        if key > best_key:
            best, best_key = candidate, key
    return best

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail(
                    "루트 모듈만 Bun 툴체인의 기본 이름을 바꿀 수 있다. " +
                    "외부 저장소 전역 이름 공간의 충돌을 막기 위한 제약이다.",
                )
            registrations.setdefault(toolchain.name, []).append(toolchain.bun_version)

    for name, versions in registrations.items():
        # 같은 버전을 여러 모듈이 선언하는 것은 정상이다. 실제로 서로 다른
        # 버전이 선언됐을 때만 경고한다.
        versions = sorted({v: None for v in versions}.keys())
        if len(versions) > 1:
            selected = _max_version(versions)

            # buildifier: disable=print
            print("NOTE: bun 툴체인 {} 에 여러 버전 {} 이 있어 {} 를 선택했다.".format(
                name,
                versions,
                selected,
            ))
        else:
            selected = versions[0]

        bun_register_toolchains(name = name, bun_version = selected)

    # 네트워크 해석이 없고 lockfile 의 integrity 로 고정되므로 재현 가능하다.
    return module_ctx.extension_metadata(reproducible = True)

bun = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {"toolchain": bun_toolchain},
    # OS/arch 에 따라 내려받는 파일이 달라지지 않는다(전 플랫폼을 항상 선언).
    os_dependent = False,
    arch_dependent = False,
)
