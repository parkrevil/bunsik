# rules_bun 실행 계획

> 대상: `tools/rules_bun` — 커밋 `601f5f3` 기준
> 선행 문서: [`rules_bun-design.md`](rules_bun-design.md) (아키텍처), [`bazel-rule-authoring.md`](bazel-rule-authoring.md) (Bazel 계약)
> 이 문서: **무엇을 어떤 순서로 할 것인가**와 **왜 그렇게 정했는가**

---

## 0. 현재 상태

툴체인 계층만 선다. 실제 룰(`bun_library` / `bun_binary` / `bun_test`)은 0줄이다.

```
bun/  defs.bzl  extensions.bzl  repositories.bzl  toolchain.bzl
      private/  action.bzl  hardening.bzl  paths.bzl  platforms.bzl
                providers.bzl  semver.bzl  toolchains_repo.bzl  versions.bzl
      tests/    action_test.bzl  hardening_test.bzl
                platform_transition.bzl  semver_test.bzl
docs/  BUILD.bazel  defs.md  toolchain.md
e2e/smoke/  MODULE.bazel  BUILD.bazel  verify.bzl  platforms/
```

검증되는 것 — buildifier 경고 0. **§3.1 완료 후 `bazel test //...` 하나로 10개가 전부 돈다**(이전에는 룰셋 5 + e2e 5로 갈려 있었다). `e2e/smoke` 는 소비자 관점 검증 1개만 남았다.

| 테스트 | 무엇을 잡나 |
|---|---|
| `semver_test_0/1/2` | 버전 비교 (정렬·prerelease·키 형태) |
| `docs:update_0/1_test` | 커밋된 Stardoc 문서가 소스와 어긋나면 실패 |
| `hardening_emitted_test` | 모든 룰이 하드닝 인자를 방출하는가 (analysistest) |
| `hardening_test` | 그 인자가 공격을 실제로 막는가 (실행) |
| `cross_{darwin,linux,windows}_test` | 크로스 컴파일 (플랫폼 transition) |

---

## 1. 구조 결정과 근거

공식 룰셋 5종을 클론해 파일 단위로 대조한 결과다. **사례 하나가 아니라 전수조사다.**

### 1.1 최상위 배치 — 공식 스캐폴드와 4/4 일치. 변경 없음

```
bazel-contrib/rules-template   defs.bzl  extensions.bzl  repositories.bzl  toolchain.bzl
rules_bun                      defs.bzl  extensions.bzl  repositories.bzl  toolchain.bzl
```

`bazel-rule-authoring.md` §10이 *"템플릿: `bazel-contrib/rules-template` 기반"* 으로 확정했고 실제로 그대로다.

### 1.2 `private/` 평면 유지 — 하위그룹 만들지 않는다

| 룰셋 | `private/*.bzl` 평면 | 하위그룹 |
|---|---|---|
| **rules-template (스캐폴드)** | 2 | **0** |
| rules_go | 14 | 5 |
| rules_ruby | 18 | 8 |
| rules_js | 13 | 10 |
| rules_python | 87 | 7 |
| **rules_bun (현재)** | **8** | **0** |

하위그룹은 **파일 수가 아니라 곁딸린 자산** 때문에 생긴다.

```
rules_ruby/ruby/private/binary/   BUILD  binary.cmd.tpl  binary.sh.tpl
```

`rules_python`은 이름에 `toolchain` 이 들어간 파일만 평면에 13개를 두고도 `toolchain/` 을 만들지 않았다. 우리는 8개에 자산이 없다.

> 측정: `find <룰셋>/<lang>/private -mindepth 1 -maxdepth 1 -name '*.bzl' | wc -l`
> `rules_js` 는 `js/private`(13) 과 `npm/private`(25) 가 별도 최상위 디렉터리다.
> 언어 디렉터리 하나만 센다.

### 1.3 `repositories.bzl` 최상위 공개 유지

공식 스캐폴드의 `mylang/repositories.bzl`은 **76줄이고 repo rule + 등록 매크로가 한 파일에 있다.** 우리 107줄은 integrity 오버라이드가 더해진 것뿐이다. `rules_go`(`deps.bzl`)·`rules_python`(`repositories.bzl`)도 최상위다.

`rules_ruby`의 `deps.bzl`(22줄 재export)은 파일이 많아진 뒤의 정리이지 출발 형태가 아니다.

### 1.4 툴체인 3계층 — 선례대로

| 계층 | rules_ruby | rules_bun |
|---|---|---|
| 공개 룰 | `ruby/toolchain.bzl` | `bun/toolchain.bzl` — 생성된 BUILD가 `load` 한다. private로 못 내린다 |
| 공개 repo API | `ruby/deps.bzl` | `bun/repositories.bzl` |
| private 부품 | `ruby/private/toolchain/*` | `bun/private/{platforms,versions,toolchains_repo}.bzl` |

---

## 2. 기각한 대안

| 제안 | 기각 사유 |
|---|---|
| `repositories.bzl` → `private/toolchain/` | 공식 스캐폴드가 최상위에 둔다(§1.3). 근거였던 `rules_ruby` 하나만 다르다 |
| `private/toolchain/` 하위그룹 신설 | 스캐폴드 하위그룹 0개, `rules_python`은 평면 87개(§1.2). 곁딸린 자산이 없다 |
| 룰셋 `MODULE.bazel`에서 툴체인 선언 삭제 | **이미 했고 잘못이었다.** §3.1 참조 |

---

## 3. 리팩터 — `bun_library` 착수 전에 끝낸다

이후에는 전부 breaking change가 된다. 소비자 0, e2e 1개인 지금만 무료다.

### 3.1 [1순위] 룰셋이 자기 툴체인을 갖게 한다

**문제.** 앞서 "소비자가 버전을 못 내린다"는 이유로 룰셋 `MODULE.bazel`의 툴체인 선언을 삭제했다. 그 결과 룰셋 워크스페이스에서 툴체인이 필요한 테스트를 인스턴스화할 수 없게 됐고, `e2e/smoke`를 만들고 테스트를 두 워크스페이스로 쪼개고 `bun/tests/`를 public으로 열어 테스트 룰이 소비자에게 새게 됐다.

**이건 거짓 딜레마였다.** `dev_dependency = True`는 그 모듈이 루트일 때만 적용되므로 둘 다 얻는다. `rules_js/MODULE.bazel`이 쓰는 패턴이다.

```python
####### Dev dependencies ########
register_toolchains(..., dev_dependency = True)
```

**완료 판정** — `cd tools/rules_bun && bazel test //bun/tests:all` 이 툴체인 필요한 테스트를 포함해 통과하고, `e2e/smoke` 5개도 여전히 통과한다(소비자 버전 선택 무영향).

### 3.2 [1순위] provider 개명 — `BunInfo` → `BunRuntimeInfo`

**문제.** 현재 `BunInfo` = `{bun, version, tool_files}`(툴체인용). 설계 §4.4의 `BunInfo` = `{sources, types, npm_deps, ...}`(라이브러리용). **겹치는 필드 0개인데 이름이 같다.** `defs.bzl`이 이미 공개했으므로 `bun_library`를 한 줄이라도 쓰면 breaking change가 된다.

**생태계 관례** — `<Lang>Info`는 라이브러리 provider에 예약된다.

| 룰셋 | 라이브러리 | 툴체인 payload |
|---|---|---|
| rules_python | `PyInfo` | `PyRuntimeInfo` |
| rules_go | `GoLibrary` | `GoSDK` |
| rules_js | `JsInfo` | — |

**결정** — 라이브러리가 `BunInfo`를 가져가고 툴체인은 `BunRuntimeInfo`. 동시에 `ToolchainInfo(buninfo=...)` → `ToolchainInfo(runtime=...)`. `buninfo`는 타입명을 필드명에 반복하는 중복이다.

**완료 판정** — `grep -rn "BunInfo\|buninfo" tools/rules_bun` 결과가 신설 `bun/providers.bzl`과 문서에만 남는다.

### 3.3 [1순위] `bun/providers.bzl` 신설 (공개)

`bazel-rule-authoring.md` §1이 `bun/providers.bzl ← 공개 provider`로 지정했는데 구현은 `private/`에 있고 `defs.bzl`이 재export한다. `rules_js`가 `js/providers.bzl`(공개) + `js/private/js_info.bzl`(구현) 2단이다. `defs.bzl`은 룰만 공개한다.

### 3.4 [2순위] `private/toolchain_type.bzl`

`BUN_TOOLCHAIN_TYPE`이 공개 `defs.bzl`에만 있어 `private/`이 쓸 수 없다. 새 룰 3개가 각자 툴체인을 잡기 전에 옮긴다.

### 3.5 [2순위] `hardening` → `reproducible`

**로직과 테스트가 반대 프레임을 쓴다.**

| 파일 | 언어 |
|---|---|
| `hardening.bzl` | *"목적은 재현 가능한 빌드다"* |
| `hardening_test.bzl` | *"공격용 bunfig.toml"*, `_ATTACK_PRELOAD`, `__POISONED__` |

실제 목적은 보안이 아니라 재현성이다. 파일명과 테스트 언어를 함께 통일한다.

### 3.6 [2순위] `tests/`에서 테스트 아닌 것 분리

`platform_transition.bzl`의 `with_platform`은 `test = True` 없는 일반 룰이고, `action_test.bzl`은 픽스처 룰과 테스트를 겸한다. `bun/tests/fixtures.bzl`로 분리한다.

### 3.7 [3순위] `docs/`에 `extensions`·`providers` 추가

`bzl_library`가 4개인데 `stardoc_with_diff_test`는 2개에만 걸려 있다. **소비자가 실제로 타이핑하는 `bun.toolchain(bun_version=..., integrity=...)` 에 문서가 없다.**

### 3.8 [3순위] 선행 문서 갱신

`bazel-rule-authoring.md` §1과 `rules_bun-design.md` §4.4가 구현과 어긋난 채 방치돼 있다. **다음 단계의 설계 근거로 쓰이는 문서다.**

| 문서 | 구현 | 어느 쪽이 맞나 |
|---|---|---|
| `bun/providers.bzl` 공개 | `private/` + 재export | 문서 (§3.3에서 구현을 고침) |
| `private/test/*.bzl` | `bun/tests/` | 구현 (`rules_ruby`가 `ruby/tests/`) |
| `BunInfo` 필드 정의 | 툴체인용으로 점유됨 | §3.2에서 정리 |

---

## 4. 실행 순서

```
1  룰셋 툴체인 (dev_dependency)        ← 완료 (601f5f3)
2  BunInfo → BunRuntimeInfo
3  bun/providers.bzl 신설               (2 선행)
4  private/toolchain_type.bzl
5  hardening → reproducible
6  tests/fixtures.bzl 분리
7  docs/ 확장                           (2,3 선행)
8  선행 문서 갱신                        (2,3,5,6 선행)
───────────────────────────────────────
   여기서 bun_library TDD 착수
```

1~8은 파일 이동·개명 수준이고 기존 테스트 10개가 회귀를 잡는다.

---

## 5. 미결 — 결정 필요

### CI

공식 룰셋 4/4가 `.github/workflows/`를 갖는다. 우리는 없다(이전에 제외 결정).

없을 때의 대가:
- `e2e/smoke`는 `.bazelignore` 밖이라 **루트에서 `bazel test //...` 에 안 잡힌다.** 사람이 따로 들어가서 돌려야 한다
- 크로스 플랫폼 3종도 e2e 안이라 같은 문제
- 패치(`patches/*.patch`)가 NestJS 업그레이드로 깨지는 걸 감지할 자동 수단이 없다

대안 — CI 없이 가려면 `bazel test //...` 하나로 전부 도는 구조를 만들어야 한다. §3.1이 그 절반을 해결한다.

---

## 6. 다음 단계 (`bun_library` 이후)

| 시점 | 작업 |
|---|---|
| `bun_library` 후 | `examples/` — 공식 4/4 보유, 보여줄 룰이 생긴 뒤 |
| `bun_binary` 후 | `paths.bzl` → `runfiles_paths.bzl`. 런처 템플릿을 `.sh.tpl`/`.cmd.tpl`로 분리(Windows) |
| 액션 3종 초과 | `private/actions/` 승격 |
| 두 번째 `tag_class` | `extensions.bzl` 분해 |

---

## 부록: 이 계획이 고치는 과거 실수

기록으로 남긴다. 같은 실수를 반복하지 않기 위해서다.

| 실수 | 발견 경위 |
|---|---|
| `bun_action`을 "강제 지점"이라 문서화했으나 호출자 0명 | 감사. 하드닝 제거해도 테스트 통과 |
| `hardening_test`가 공격 파일을 `bazel-out`에 만들어 재현 실패 | 변이 테스트 |
| `build_test` 3개가 `--platforms`를 안 걸어 같은 걸 세 번 빌드 | 변이 테스트 |
| `e2e/smoke/platforms/` 참조 0건 (죽은 코드) | 감사 |
| 툴체인 선언 삭제 — `dev_dependency`를 몰라 거짓 딜레마를 만듦 | 감사 |
| 성능 수치 20배 → 실제 2배 (워밍업 오염) | 자체 재측정 |

공통점 — **전부 "만들고 나서 테스트를 붙였기 때문"이다.** `bun_library`부터는 TDD로 간다. [`rules_bun-testplan.md`](rules_bun-testplan.md) 참조.
