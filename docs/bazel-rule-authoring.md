# Bazel 룰 작성 레퍼런스

> 대상: Bazel 9.2.0 / bzlmod 전용. `rules_bun` 작성에 필요한 것만.
> 근거: 공식 문서 + `aspect-build/rules_js` 소스(146 `.bzl` / 33,242줄) + 로컬 실험.
> 표기: **[검증]** = 로컬에서 실행해 확인. **[문서]** = 공식 문서 근거.

---

## 1. 형식과 언어

| 질문 | 답 |
|---|---|
| 언어 | **Starlark** — Python 유사 방언. `while`·재귀·I/O 없음. 튜링 불완전, 결정적 |
| 파일 | `.bzl` (로직) + `BUILD.bazel` (타겟 선언) |
| 형태 | 별도 저장소 + bzlmod 모듈. 관례상 `<org>_rules_<lang>` |
| 무거운 로직 | Starlark에 넣지 않는다. **별도 바이너리로 빼서 액션으로 실행** |

Starlark는 의도적으로 약한 언어다. lockfile 파싱·그래프 계산 같은 건 Starlark로 하지 말고 **Bun/TypeScript 바이너리**로 작성해 액션으로 돌린다. rules_js도 같은 구조다.

**저장소 레이아웃** (공식 권장 + rules_js 실제 구조):

```
rules_bun/
  MODULE.bazel
  bun/
    BUILD.bazel
    defs.bzl          ← 공개 API. 사용자는 이것만 load
    providers.bzl     ← 공개 provider
    extensions.bzl    ← module extension
    private/
      *.bzl           ← 구현. 외부 load 금지
      test/*.bzl      ← 룰 자체 테스트
  tests/
  examples/
  docs/               ← Stardoc 생성물
```

`defs.bzl`은 재export만 한다. 구현은 전부 `private/`. rules_js의 `js/defs.bzl`이 정확히 이 형태다.

---

## 2. 확장 지점 5가지 — 언제 무엇을 쓰나

| 지점 | 실행 시점 | 용도 | rules_bun에서 |
|---|---|---|---|
| **macro** | 로딩 | 타겟 여러 개를 묶어 선언 | 최소화. 디버깅·query가 어려워진다 |
| **rule** | 분석 | 액션 생성, provider 반환 | `bun_library` / `bun_binary` / `bun_test` |
| **aspect** | 분석 | 의존 그래프를 따라 부가 작업 | 타입체크(`tsc`)를 그래프 전체에 전파 |
| **repository rule** | 로딩(페치) | 외부 소스 트리 생성 | npm 패키지 페칭 |
| **module extension** | 로딩 | 모듈 그래프를 읽어 repo 생성 | `bun.lock` 번역 |

**[문서] 규칙: 가능하면 macro보다 rule.** macro는 분석 전에 펼쳐져서 `bazel query` 결과와 오류 메시지를 망가뜨린다.

---

## 3. `rule()` 계약

```python
def _bun_library_impl(ctx):        # 이름은 _<rule>_impl, 반드시 private
    out = ctx.actions.declare_file(ctx.label.name + ".js")
    ctx.actions.run(...)
    return [DefaultInfo(files = depset([out])), BunInfo(...)]

bun_library = rule(
    implementation = _bun_library_impl,
    attrs = {...},
    provides = [BunInfo],          # 계약 명시 → 위반 시 분석 단계에서 실패
    toolchains = ["//bun:toolchain_type"],
    doc = "...",                   # Stardoc 입력
)
```

**핵심 제약 [문서]**
- 구현 함수는 **분석 단계**에서만 돈다. 파일 내용을 읽을 수 없다.
- 모든 액션 입력을 미리 선언해야 한다. 선언 안 한 건 샌드박스에서 못 읽는다.
- 선언한 출력은 반드시 어떤 액션이 만들어야 한다.

**속성 관례 [문서]**
- 표준 이름을 쓴다: `srcs`, `deps`, `data`, `deps`.
- private 속성은 `_` 접두 + `default` 필수. 런처 템플릿·툴이 여기 들어간다.
- `attr.label(cfg = "exec")` — 빌드 중 **실행되는** 도구.
- `attr.label(providers = [BunInfo])` — 의존성 타입 강제.

---

## 4. 액션

### 4.1 `ctx.actions.*`

| 메서드 | 용도 |
|---|---|
| `run` | 실행파일 호출. 기본 수단 |
| `run_shell` | 셸 명령. 이식성 때문에 최소화 |
| `write` | 문자열/Args를 파일로 |
| `expand_template` | 런처 스크립트 생성 (rules_js가 쓰는 방식) |
| `symlink` | 심볼릭 링크. **[검증] 출력은 execroot 절대경로이고 `internal` 액션이라 원격 실행 대상이 아니다** |
| `declare_file` / `declare_directory` | 출력 선언 |

`run()`의 중요 파라미터: `executable`, `tools`(runfiles까지 자동 포함), `inputs`, `outputs`, `mnemonic`, `env`, `use_default_shell_env`, `execution_requirements`, `exec_group`.

**hermeticity**: `use_default_shell_env = False`(기본)를 유지하고 `env`를 명시한다. 켜면 사용자 환경이 새어든다.

### 4.2 `Args` — 성능의 핵심 [문서]

> "depset 확장을 실행 단계로 미룬다. 순수하게 더 빠를 뿐 아니라 메모리를 **90% 이상** 줄이기도 한다."

```python
args = ctx.actions.args()
args.add("--out", out)
args.add_all(deps_depset, map_each = _to_path)   # depset을 그대로 넘긴다
args.use_param_file("@%s", use_always = True)     # 인자 수천 개일 때 필수
args.set_param_file_format("multiline")
```

**절대 하지 말 것**: `depset.to_list()`로 펼쳐 문자열로 이어붙이기. 목록/문자열 연결은 O(N²)가 된다.

param file을 쓰면 **우리 툴(Bun 스크립트)이 `@file` 인자를 읽을 수 있어야 한다.** 이건 툴 쪽 요구사항이다.

### 4.3 depset 규칙 [문서]

```python
depset(direct = [my_file], transitive = [d[BunInfo].transitive_sources for d in ctx.attr.deps])
```

- 전이 정보는 **항상** depset. 리스트/딕트는 현재 룰의 로컬 정보에만.
- `to_list()`는 **종단 룰(binary)에서 한 번만**. 라이브러리 룰에서 호출하면 O(N²).
- 루프 안에서 `depset()`을 재할당하지 않는다 (깊은 중첩 발생).

---

## 5. Provider

```python
BunInfo = provider(
    doc = "...",
    fields = {"sources": "...", "transitive_sources": "..."},
)
```

rules_js의 `JsInfo`가 좋은 참고다 — `sources` / `types` / `transitive_sources` / `transitive_types` / `npm_sources`를 나눠 갖고, **생성자 함수를 따로 두어 타입을 검증**한다(`if type(target) != "Label": fail(...)`). 우리도 같은 패턴을 쓴다.

`OutputGroupInfo`로 기본 출력이 아닌 것들을 노출한다.

---

## 6. 설정 (Configuration) — 오늘 틀린 지점

### 6.1 exec vs target [검증]

`cfg = "exec"`로 참조된 타겟은 **별도 설정에서 다시 빌드된다.** 같은 링크 타겟을 target/exec 양쪽에서 참조하면:

```
소스 20개 → 42 액션 (target 20 + exec 20 + 소비자 + internal)
bazel-out/k8-fastbuild/bin/...   ← target
bazel-out/k8-opt-exec/bin/...    ← exec, 완전 별개 사본
```

**정확히 2배.** Starlark에는 exec 설정을 지우는 transition이 없다. 대응은 `rules_bun-design.md` §6.3.

### 6.2 transition [문서]

```python
def _impl(settings, attr):
    return {"//command_line_option:cpu": "arm64"}

my_transition = transition(implementation = _impl, inputs = [], outputs = [...])
```

- **incoming**(`rule(cfg=...)`) = 자기 설정 변경, 1:1만.
- **outgoing**(`attr.label(cfg=...)`) = 의존성 설정 변경, 1:N 가능.
- transition이 붙은 속성은 `ctx.attr.dep`가 **리스트가 된다**(단일 라벨이어도).
- **설정 폭발 주의**: 체인되면 지수적으로 configured target이 늘어난다.

`bun_executable`의 크로스 컴파일에 필요하다.

### 6.3 exec group [문서]

한 룰의 액션들이 서로 다른 실행 플랫폼/툴체인을 요구할 때 쓴다. 테스트 룰에는 `test` exec group이 기본 존재한다.

---

## 7. executable / test 룰 계약

### 7.1 구조 (rules_js 패턴)

공통 `attrs`/`toolchains`를 `_lib`에 모으고 `bun_binary`(`executable = True`)와 `bun_test`(`test = True`)가 공유한다. 런처는 `expand_template`으로 생성한다.

### 7.2 runfiles

```python
rf = ctx.runfiles(files = [...])
rf = rf.merge_all([d[DefaultInfo].default_runfiles for d in ctx.attr.deps])
```

- `symlinks` / `root_symlinks`로 커스텀 배치. **같은 경로에 두 파일을 매핑하면 빌드 실패.**
- `collect_data`/`collect_default`는 쓰지 않는다(공식 권고).
- **[검증] runfiles 심볼릭 링크는 realpath로 풀린다.** 대상이 소스 트리면 해석이 그쪽으로 탈출한다 — `rules_bun-design.md` §2.2 C.

### 7.3 테스트 환경 [문서]

`XML_OUTPUT_FILE`(JUnit XML), `TEST_TMPDIR`, `TEST_SRCDIR`, `TESTBRIDGE_TEST_ONLY`(= `--test_filter`), `TEST_SHARD_INDEX`/`TEST_TOTAL_SHARDS`/`TEST_SHARD_STATUS_FILE`(샤딩 시 반드시 touch), `TEST_UNDECLARED_OUTPUTS_DIR`. 종료코드 0 = 통과, 그 외 = 실패.

### 7.4 커버리지 [문서]

```python
coverage_common.instrumented_files_info(
    ctx,
    source_attributes = ["srcs"],
    dependency_attributes = ["deps", "data"],
    extensions = ["ts", "tsx", "js"],
)
```

`ctx.configuration.coverage_enabled`로 분기한다. rules_js는 이때만 커버리지 부트스트랩 파일을 런처에 주입한다 — 같은 패턴을 쓴다.

### 7.5 validation action [문서]

타입 체크(`tsc --noEmit`)가 정확히 이 사례다.

```python
return [
    DefaultInfo(files = depset([main_out])),
    OutputGroupInfo(_validation = depset([validation_out])),
]
```

`_validation` 출력 그룹은 `--output_groups` 값과 무관하게 **항상 요청되고, 빌드 임계 경로를 막지 않고 병렬로 돈다.** 검증 출력은 `DefaultInfo`나 다른 액션 입력에 넣지 않는다. `--run_validations`로 끌 수 있다.

**주의**: exec 설정에서 빌드되거나 툴로 참조되면 validation은 실행되지 않는다.

---

## 8. 룰 테스트 — **[검증] 동작 확인함**

`bazel_skylib`의 `analysistest`로 **실행 없이 분석 단계에서** provider와 액션을 단언한다.

```python
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _provider_test_impl(ctx):
    env = analysistest.begin(ctx)
    tut = analysistest.target_under_test(env)
    asserts.true(env, BunInfo in tut)
    return analysistest.end(env)

provider_test = analysistest.make(_provider_test_impl)

def _action_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    asserts.equals(env, "BunCompile", actions[0].mnemonic)
    return analysistest.end(env)
```

- 대상 타겟은 `tags = ["manual"]`로 막아둔다.
- `config_settings`로 특정 플래그 조합에서의 동작을 테스트할 수 있다.
- `expect_failure = True`로 실패 경로도 테스트한다.

**이게 왜 중요한가**: `rules_bun-design.md`에서 반증된 결론 6개는 전부 "돌려봐야 아는" 동작이었다. analysistest로 고정하면 회귀를 막는다. **룰을 한 줄 쓸 때마다 테스트를 같이 쓴다.**

---

## 9. 문서화·배포

- **Stardoc**: `doc=` 인자에서 API 문서를 자동 생성. `docs/`에 커밋하고 CI에서 최신 여부를 검사.
- **배포**: `MODULE.bazel`에 모듈명, README에 복붙용 스니펫, GitHub Actions CI, 최종적으로 Bazel Central Registry.
- `bazel-contrib/rules-template`이 이 전체를 갖춘 템플릿이다. **처음부터 이걸로 시작하는 게 맞다.**

---

## 10. rules_bun에 확정 적용할 결정

| 항목 | 결정 |
|---|---|
| 시작 위치 | 모노레포 내 `//tools/rules_bun`. 굳으면 별도 저장소로 분리 |
| 템플릿 | `bazel-contrib/rules-template` 기반 |
| 무거운 로직 | Bun/TypeScript 바이너리로 분리 (lockfile 파서, 오라클 그래프 덤프, 링크 플래너) |
| 인자 전달 | `Args` + param file. 툴이 `@file`을 읽도록 작성 |
| 전이 정보 | 전부 depset. `to_list()`는 종단 룰에서만 |
| 타입 체크 | aspect + `_validation` 출력 그룹 |
| 테스트 | 룰마다 `analysistest`. 반증된 6개 결론을 회귀 테스트로 고정 |
| macro | 최소화 |

---

## 부록: 아직 안 읽은 것

정직하게 남긴다. 필요해지면 그때 읽는다.

- `platforms` / `constraints` 상세 (툴체인 3플랫폼 확장 시)
- persistent worker 구현 상세 (`tsc` 워커화할 때)
- `--incompatible_*` 마이그레이션 플래그 목록
- Windows 특수사항 (심볼릭 링크 권한, `--enable_runfiles`)
- BCR 실제 배포 절차
