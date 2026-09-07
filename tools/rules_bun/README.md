# rules_bun

[Bun](https://bun.com) 을 1급 툴체인으로 쓰는 Bazel 룰셋.
Node.js 설치를 요구하지 않는다.

> **상태: 뼈대.** 툴체인 계층만 동작한다. `bun_library` / `bun_binary` /
> `bun_test` 는 아직 없다. 설계는 [`docs/rules_bun-design.md`](../../docs/rules_bun-design.md)
> 를 참조한다.

## 요구사항

Bazel 9.2.0 이상, bzlmod 전용. `WORKSPACE` 는 지원하지 않는다.

## 사용법

`MODULE.bazel`:

```python
bazel_dep(name = "rules_bun", version = "0.0.0")
local_path_override(
    module_name = "rules_bun",
    path = "tools/rules_bun",
)

bun = use_extension("@rules_bun//bun:extensions.bzl", "bun")
bun.toolchain(bun_version = "1.4.2")
use_repo(bun, "bun_toolchains")

register_toolchains("@bun_toolchains//:all")
```

룰에서 툴체인을 쓴다:

```python
load("@rules_bun//bun:defs.bzl", "BUN_TOOLCHAIN_TYPE")

def _impl(ctx):
    bun = ctx.toolchains[BUN_TOOLCHAIN_TYPE].buninfo.bun
    ...

my_rule = rule(implementation = _impl, toolchains = [BUN_TOOLCHAIN_TYPE])
```

## 공개 API

`//bun:defs.bzl` 만 load 한다. `//bun/private/...` 는 내부 구현이다.

| 심볼 | 설명 |
|---|---|
| `BUN_TOOLCHAIN_TYPE` | 룰의 `toolchains` 속성에 넣는 툴체인 타입 |
| `BunInfo` | `bun`(File), `version`(string), `tool_files` 를 담는 provider |

## 지원 플랫폼

linux-x64 / linux-aarch64 / darwin-x64 / darwin-aarch64 / windows-x64.

Bun 바이너리는 릴리스 공식 `SHASUMS256.txt` 에서 유도한 `integrity` 로
검증하며 내려받는다. 툴체인은 `exec_compatible_with` 만 제약하므로
크로스 컴파일이 성립한다.

> Windows 는 실행기가 없어 **미검증**이다.

## 재현 가능한 빌드

Bun 은 실행 시점의 주변 상태(작업 디렉터리의 `bunfig.toml` · `.env`,
누락된 패키지의 npm 자동 설치)를 읽어 빌드 재현성을 깬다.
모든 Bun 액션은 [`bun/private/action.bzl`](bun/private/action.bzl) 의
`bun_action()` 을 거치며, 거기서 하드닝이 강제된다. 근거와 실측은
[`bun/private/hardening.bzl`](bun/private/hardening.bzl) 의 주석에 있다.

`//bun/tests:hardening_test` 가 이 방어를 회귀 검증한다.

## 개발

```bash
bazel build //...          # 룰셋 빌드
bazel test  //...          # 테스트
cd e2e/smoke && bazel build //:verify   # 소비자 관점 검증
```

`e2e/smoke` 는 별도 모듈이다. 룰셋의 `MODULE.bazel` 은 툴체인 버전을
선언하지 않으므로(소비자가 버전을 내릴 수 있어야 한다) 자체 검증은
여기서 한다.

## 라이선스

MIT. [`LICENSE`](LICENSE) 참조.
