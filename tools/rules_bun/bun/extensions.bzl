"""bzlmod module extension — Bun 툴체인을 설치한다.

모든 모듈이 기본 이름("bun") 아래 버전을 선언할 수 있고, 그중 최신이 선택된다.
루트 모듈만 다른 이름으로 추가 툴체인을 선언할 수 있다.
"""

load("//bun:repositories.bzl", "bun_register_toolchains")
load("//bun/private:semver.bzl", "max_version")

_DEFAULT_NAME = "bun"

bun_toolchain = tag_class(attrs = {
    "name": attr.string(
        doc = "생성될 저장소 이름의 기준. 기본값 변경은 루트 모듈만 허용된다.",
        default = _DEFAULT_NAME,
    ),
    "bun_version": attr.string(doc = "사용할 Bun 버전.", mandatory = True),
    "integrity": attr.string_dict(
        doc = "플랫폼 -> integrity. 룰셋이 모르는 버전을 쓸 때 넘긴다. " +
              "값은 릴리스의 공식 SHASUMS256.txt 에서 얻는다.",
    ),
})

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name != _DEFAULT_NAME and not mod.is_root:
                fail(
                    "루트 모듈만 Bun 툴체인의 기본 이름을 바꿀 수 있다. " +
                    "외부 저장소 전역 이름 공간의 충돌을 막기 위한 제약이다.",
                )
            registrations.setdefault(toolchain.name, {})
            registrations[toolchain.name][toolchain.bun_version] = toolchain.integrity

    for name, declared in registrations.items():
        # 같은 버전을 여러 모듈이 선언하는 것은 정상이다. 실제로 서로 다른
        # 버전이 선언됐을 때만 경고한다.
        versions = sorted(declared.keys())
        if len(versions) > 1:
            selected = max_version(versions)

            # buildifier: disable=print
            print("NOTE: bun 툴체인 {} 에 여러 버전 {} 이 있어 {} 를 선택했다.".format(
                name,
                versions,
                selected,
            ))
        else:
            selected = versions[0]

        bun_register_toolchains(
            name = name,
            bun_version = selected,
            integrity = declared[selected],
        )

    # 네트워크 해석이 없고 lockfile 의 integrity 로 고정되므로 재현 가능하다.
    return module_ctx.extension_metadata(reproducible = True)

bun = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {"toolchain": bun_toolchain},
    # OS/arch 에 따라 내려받는 파일이 달라지지 않는다(전 플랫폼을 항상 선언).
    os_dependent = False,
    arch_dependent = False,
)
