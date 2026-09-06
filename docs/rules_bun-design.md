# rules_bun 설계 문서

> 상태: **개정 2판** — 적대적 리뷰 3회(Bazel / Bun·npm / Codex) 반영
> 초안의 주요 결론 6개가 반증되어 철회·교체됐다. 철회 내역은 §7 하단 참조.
> 대상: Bazel 9.2.0 / Bun 1.4.2 / bzlmod 전용
> 목표: `rules_js` + `rules_ts`를 완전히 대체하는 Bun 네이티브 Bazel 룰셋

---

## 1. 목표와 비목표

### 목표

1. **Bun을 1급 툴체인으로** 취급한다. Node.js를 설치 요건에서 제거한다.
2. `bun.lock`을 단일 진실 공급원으로 삼아 **완전 재현 가능(hermetic)** 한 의존성 페칭을 한다.
   ⚠️ git 의존성은 예외다 — lockfile integrity가 tarball과 일치하지 않는다 (§2.1 I, §6.2).
3. 라이브러리 / 바이너리 / 테스트 / 번들 / 단일 실행파일을 모두 커버한다.
4. TypeScript를 **별도 룰셋 없이** 처리한다 — 트랜스파일은 `bun build`, 타입 체크만 `tsc`.
   ⚠️ **초안의 "컴파일 단계 자체가 불필요"는 §2.7에서 반증됐다.** Bun의 트랜스파일 시맨틱이 프로세스 cwd 단위로 고정되므로, 여러 패키지가 한 프로세스에 로드되는 모노레포에서는 **패키지별 사전 컴파일이 필수**다. `rules_ts`를 안 쓴다는 뜻이지 컴파일이 없다는 뜻이 아니다.
5. 원격 캐시에서 동작한다. **원격 실행은 M7의 검증 대상이지 전제가 아니다** (§6, `ctx.actions.symlink`은 로컬 internal 액션이다).

### 비목표

- `rules_js`와의 API 호환성. 마이그레이션 경로만 문서화한다.
- Node.js 런타임 지원. `bun build --target=node` 산출물은 만들되 Node로 **실행**하지는 않는다.
- npm 퍼블리시 워크플로 (1차 범위 밖, `bun pm pack` 위에 나중에 얹는다).

---

## 2. 조사에서 확인된 사실

아래는 전부 **로컬에서 직접 실행해 검증한 결과**다. 문서만 읽고 추정한 항목은 §7에 따로 표시했다.

### 2.1 Bun 측

**(A) `bun.lock` v2 포맷은 Bazel 번역에 충분하다.**

```json
{
  "lockfileVersion": 2,
  "configVersion": 1,
  "workspaces": { "": { "name": ..., "dependencies": {...} }, "pkgs/a": {...} },
  "overrides": { "semver": "7.6.3" },
  "packages": {
    "rxjs":       ["rxjs@7.8.2", "", { "dependencies": { "tslib": "^2.1.0" } }, "sha512-dhKf..."],
    "@w/a":       ["@w/a@workspace:pkgs/a"],
    "lodash-es":  ["lodash@4.17.21", "", {}, "sha512-v2kD..."],
    "tinycolor":  ["TinyColor@github:bgrins/TinyColor#a93228a", {}, "bgrins-TinyColor-a93228a", "sha512-xl05..."],
    "@nuxtjs/opencollective/chalk": ["chalk@4.1.2", "", {...}, "sha512-..."]
  }
}
```

엔트리 형태가 **종류마다 다르다**. 파서는 튜플 길이와 원소 타입으로 분기해야 한다.

| 종류 | 튜플 | 비고 |
|---|---|---|
| npm 레지스트리 | `[resolution, registry, meta, integrity]` (4) | `registry`가 `""`면 기본 레지스트리 |
| workspace | `[resolution]` (1) | `name@workspace:<path>` |
| git/github | `[resolution, meta, folderName, integrity]` (4) | **2번째 원소가 문자열이 아니라 객체** |
| alias | 키 ≠ 해석된 이름 | `"lodash-es"` → `lodash@4.17.21` |
| 중첩(버전 충돌) | 키가 `"parent/child"` 경로 | `node_modules/parent/node_modules/child` 위치를 뜻함 |

`meta` 객체에 담기는 것: `dependencies`, `peerDependencies`, `optionalDependencies`, `optionalPeers`, `bin`, `os`, `cpu`.

**(B) tarball URL은 lockfile에 없지만 결정적으로 유도 가능하다.** 그리고 integrity가 정확히 일치한다.

```
https://registry.npmjs.org/rxjs/-/rxjs-7.8.2.tgz
  → sha512 dhKf903U/PQZY6boNNtAGdWbG85WAbjT/1xYoZIC7FAY0yWapOBQVsVrDl58W86//e1VpMNBtRV4MaXfdMySFA==
  → lockfile integrity와 바이트 단위 일치 ✔

https://registry.npmjs.org/@nestjs/common/-/common-10.4.15.tgz   (스코프는 basename만 사용)
  → sha512 vaLg1ZgwhG29BuLDxPA9OAcIlgqzp9/N8iG0wGapyUNTf4IY4O6zAHgN6QalwLhFxq7nOI021vdRojR1oF3bqg==
  → 일치 ✔
```

⇒ `http_archive`(또는 전용 repo rule)로 패키지 단위 페칭이 가능하다. **Bun 없이도 페칭 레이어를 만들 수 있다.**

**(C) 미리 채운 캐시 + `--offline`로 완전 오프라인 설치가 된다. (핵심 검증)**

Bun 글로벌 캐시 엔트리 이름은 **종류마다 스킴이 다르다**. 내용은 압축 해제된 패키지 디렉터리다.

| 종류 | 캐시 경로 |
|---|---|
| 일반 | `rxjs@7.8.2@@@1` (= `<name>@<ver>@@<registry>@1`) |
| 스코프 | `@nestjs/` **디렉터리 아래** `common@10.4.15@@@1` — 평탄한 이름이 아니다 |
| git | `@GH@bgrins-TinyColor-a93228a@@@1` — 또 다른 스킴 |
| 기타 | `@T@<hex>@@@1` 형태도 존재 (용도 미확인) |

캐시 디렉터리에 해당 이름으로 디렉터리를 넣고:

```
BUN_INSTALL_CACHE_DIR=<dir> bun install --offline --frozen-lockfile --linker isolated --ignore-scripts
→ "3 packages installed [15.00ms]", 네트워크 접근 0, 실행 검증 통과 ✔
```

⚠️ 단, 이 캐시 네이밍(`@@@1` 접미사)은 **문서화되지 않은 내부 구현**이다. 리스크로 §7에 기록.

**(D) `--linker isolated`의 store 디렉터리 이름에 peer 해시가 붙는다.**

```
node_modules/.bun/@nestjs+core@10.4.15+491f079ccbe43826/
node_modules/.bun/@nestjs+common@10.4.15+212bbb5ae4fde332/
node_modules/.bun/rxjs@7.8.2/            ← peer 없으면 해시 없음
```

이 해시는 **lockfile에 존재하지 않는다.** ⇒ Bun의 peer 해석을 재구현하지 않는 한 Starlark에서 isolated 레이아웃을 미리 계산할 수 없다. 스코프 `/`는 `+`로 치환된다.

**(E) `bun`은 기본적으로 없는 패키지를 npm에서 자동 설치한다. — 심각한 hermeticity 구멍**

실험 중 실제로 발생한 일:

```
error: Cannot find package 'bintrees' from
  '<sandbox>/_tmp/40fe.../.bun/install/cache/shared@0.2.0@@@1/lib/shared.js'
```

내 로컬 `shared` 패키지를 못 찾자 Bun이 **npm에서 무관한 `shared@0.2.0`을 조용히 다운로드해 실행했다.**
⇒ **모든 Bazel 액션의 Bun 호출에 `--no-install`이 필수다.** 이건 선택이 아니라 안전 요구사항이다.

**(F) `--preserve-symlinks`는 realpath 탈출을 막지 못한다.** (§2.2 C 참조)

**(G) 테스트 출력은 Bazel과 맞는다. 커버리지는 조건부다.**

- `bun test --reporter=junit --reporter-outfile=$XML_OUTPUT_FILE` → Bazel이 요구하는 JUnit 스키마 그대로. `testsuites/testsuite/testcase/failure` + `file`/`line` 속성까지 포함. 실패 시 exit code 1. ✔
- `--coverage --coverage-reporter=lcov --coverage-dir=<dir>` → `lcov.info` 생성.
- ⚠️ **`lcov.info`는 테스트가 외부 소스를 import할 때만 생성된다.** 초안은 "실패 시 미생성"이라고 적었으나 **조건을 잘못 짚었다**. 통과하더라도 자기완결적인 테스트는 커버리지 파일을 만들지 않는다. 룰은 파일 부재를 정상으로 처리해야 한다.
- ⚠️ lcov의 `SF:` 경로가 **cwd 상대**로 나온다(`SF:lib.ts`). cwd가 bazel-out인 설계에서는 워크스페이스 상대 경로로 **재작성이 필수**다.

**(H) `bun test`에는 샤딩이 내장되어 있다.**

```
--shard=<val>     Run a subset of test files, e.g. '--shard=1/3'
--timings=<val>   JSON file(s) of per-file durations; balances --shard by total time
```

`--shard=1/2` / `2/2`로 4개 파일이 2+2로 정확히 분할되는 것을 확인했다.
초안 §4.4의 "Bun 자체 샤딩 플래그는 없다 → 파일 목록을 수동 분할" 은 **틀렸고**, 수동 분할은 `--timings` 기반 시간 균형까지 잃는 열등한 방법이다. 철회한다.

**(I) git 의존성의 lockfile integrity는 tarball과 일치하지 않는다. — 차단 요소**

```
codeload tar.gz 실측:  UzqZM7y7jotSRvyWoQIt1M9MBTOks4YX/VlYKodHJpFzkkjitnc/Lwulx+bnS21sKxyIfNRVFnTRbAPZrb/iow==
bun.lock 기록값:       xl05AxgsYdvksBFwDs1T0YSBccBelHCTTcpioKh8GARkTOqRYdR220slYb5N8eOCcYolB4xtaltsdKTrlt9uZQ==
                       → 완전 불일치
```

npm 패키지는 integrity가 바이트 단위로 일치했지만(§2.1 B), git 의존성은 Bun이 **자체 패킹 알고리즘으로 만든 산출물**에 대한 해시다. ⇒ `http_archive` + lockfile integrity로 git 의존성을 가져오는 것은 **구조적으로 불가능**하다. §7의 "미검증"이 아니라 페칭 설계의 **차단 요소**이며, 별도 경로가 필요하다(§6).

### 2.2 Bazel 측 — 여기가 설계를 결정한다

**(A) tree artifact(`declare_directory`)는 심볼릭 링크를 따라 걷는다. 절대 크기가 감당 불가다.**

실제 isolated 설치를 규모별로 측정:

| 구성 | 패키지 | 파일 수 (물리 → 논리) | 배율 | 바이트 (물리 → 논리) | 배율 |
|---|---|---|---|---|---|
| 소 (NestJS core만) | 22 | 3,252 → 14,838 | 4.6× | 6.4 MB → 28.8 MB | 4.5× |
| 중 (NestJS + TypeORM) | 216 | 13,661 → 56,395 | 4.1× | 69 MB → 245 MB | 3.5× |
| 대 (+ Next/React/vitest) | 306 | 24,380 → 95,413 | **3.9×** | 579 MB → **1,850 MB** | **3.2×** |

**증폭률은 초선형이 아니라 거의 상수(~4×)이며 오히려 규모가 커지면 완만히 감소한다.** 배율은 의존성 깊이가 아니라 평균 fan-in에 의해 결정되기 때문이다.

문제는 배율이 아니라 **절대 크기**다. 앱 하나의 node_modules가 1.85 GB짜리 아티팩트가 되고, 이게 링크 타겟마다 반복된다. 액션 캐시 키 계산, CAS 업로드, 원격 실행 입력 전송이 전부 이 크기를 지불한다.

> 최초 초안은 "의존성 깊이에 따라 초선형으로 증가"라고 적었으나 데이터 포인트가 1개뿐인 상태의 추측이었고, 측정 결과 **틀렸다**. 결론(A안 폐기)은 유지되지만 근거는 증가율이 아니라 절대 크기다.

**(B) tree artifact 안의 심볼릭 링크 사이클은 빌드를 실패시킨다.**

```
ERROR: error while validating output tree artifact cyc:
  [unix_jni.cc:382] .../cyc/a/up/a/up/a/up/... (Too many levels of symbolic links)
ERROR: MakeCycle cyc failed: not all outputs were created or valid
```

⇒ **폐기해야 하는 것은 "tree artifact 내부의 심볼릭 링크"이지 tree artifact 자체가 아니다.**

> 초안은 여기서 "node_modules를 tree artifact로 모델링하는 설계는 폐기"라고 결론지었다. **과잉 일반화였다.** §2.6에서 반증한다. 위 실험은 *이미 링크가 다 박힌 node_modules 전체*를 하나의 tree artifact에 넣은 것이라, 측정된 4.5×와 사이클은 전부 **내부 심볼릭 링크** 때문이다.

(보조 관측: 심볼릭 링크는 `bazel-bin`의 물리 출력에는 남아 있다. 사라지는 건 Bazel의 *논리 모델* 안에서다. 그래서 샌드박스/원격에서만 터진다 — 로컬에서 통과하고 CI에서 깨지는 최악의 패턴.)

**(C) realpath 탈출이 실재한다.**

runfiles 심볼릭 링크로 node_modules를 만들고 Bun을 실행하면:

```
error: Cannot find package 'shared' from '<source-tree>/app/main.js'
```

runfiles 링크 → execroot 링크 → **소스 트리**까지 realpath가 풀린다. 해석 워크는 소스 트리에서 시작하므로 runfiles의 node_modules를 영영 못 본다. `--preserve-symlinks`를 줘도 동일하게 실패한다.

**(D) 해결책: store에는 실제 파일, 링크 레이어에만 심볼릭 링크. 검증 완료.**

- 1st-party 소스와 3rd-party 패키지 파일을 `bazel-out`에 **실제 복사**한다.
- node_modules는 `declare_directory`가 아니라 **파일 단위 `ctx.actions.symlink`** 로 만든다 (tree artifact가 아니므로 워크/중복/사이클 문제 없음).
- cwd를 `bazel-out` 안으로 두고 실행.

결과:

```
shared.id     = <bazel-out>/bin/node_modules/.store/shared@1.0.0/node_modules/shared/index.js
c1->shared.id = <bazel-out>/bin/node_modules/.store/shared@1.0.0/node_modules/shared/index.js
same module instance: true   counter: 3
exit=0                                                                              ✔
```

**모듈 동일성이 보존된다.** 두 경로가 같은 store 파일로 realpath되기 때문이다. 이건 `reflect-metadata`, `rxjs`, NestJS DI 처럼 싱글턴/`instanceof`에 의존하는 라이브러리에 필수 조건이다. (tree artifact 방식이었다면 중복 사본이 생겨 `a === b`가 **false**가 되고 NestJS DI가 조용히 깨진다.)

**(E) 주의 — ancestor 해시 누수.** 위 실험에서 `c1`의 store 디렉터리에는 `shared` 심볼릭 링크가 없었는데도 해석에 성공했다. 조상 경로의 최상위 `node_modules/`를 타고 찾아간 것이다. 즉 **레이아웃을 대충 만들면 hoisted처럼 동작해 phantom dependency를 허용한다.** 엄격한 격리를 원하면 각 store 디렉터리에 그 패키지의 직접 의존성을 전부 심볼릭 링크로 넣어야 한다 (= Bun isolated linker가 하는 일).

### 2.3 `bun install`을 "해석 오라클"로 쓸 수 있다 — 적대적 리뷰 후 추가 검증

초안은 "링크 레이어를 우리가 소유하려면 의존성 해석도 우리가 해야 한다"고 전제하고 peer 해석기 재구현을 감수했다. **이 전제는 틀렸다.** 두 가지는 분리 가능하다.

`bun install --linker isolated` 결과(패키지 216개)를 측정한 결과:

```
nodes: 216      ← node_modules/.bun/ 의 store 디렉터리 = 패키지 인스턴스
edges: 569      ← store 내부 심볼릭 링크 = 의존성 엣지
절대경로 심볼릭 링크: 0개                                    ✔ 완전 이식 가능
```

- **peer 해시가 디렉터리 이름에 그대로 노출된다**: `@nestjs+common@10.4.15+a40073cecfde427d`.
  계산할 필요 없이 **읽으면 된다.**
- 엣지는 전부 `readlink`로 복원된다: `node_modules/.bun/proxy-addr@2.0.7/node_modules/forwarded → ../../forwarded@0.2.0/node_modules/forwarded`
- 상대 경로만 사용하므로 위치 독립적이다.

⇒ **`bun install`은 바이트 전달 수단이 아니라 해석 그래프의 오라클로 쓴다.**
해석은 Bun에게 위임하고(재구현 0), 바이트는 lockfile에서 유도한 tarball을 Bazel이 integrity 검증하며 지연 페칭하고(§2.1 B), 레이아웃은 §2.2 D 방식으로 재구성한다.

이로써 초안 최대 리스크였던 "Starlark에서 semver + peer 해석 전체 재구현"이 **설계에서 제거된다.**

### 2.4 파일 단위 심볼릭 링크는 규모를 견딘다 — 실측

채택안의 최대 미검증 리스크는 "패키지 수천 개 × 파일 수만 개를 파일 단위 액션으로 만들면 분석이 무너진다"였다. 실제 216패키지 store(13,661 파일)를 Bazel로 링크해 측정:

| 시나리오 | 액션 수 | 시간 |
|---|---|---|
| 최초 빌드 | 13,662 (**전부 internal**) | 4.3 s |
| null 빌드 (변경 없음) | 1 | 1.1 s |
| 파일 1개 변경 후 증분 | **2** | 0.3 s |

- `ctx.actions.symlink`은 전부 **internal 액션**이다. 서브프로세스를 띄우지 않으므로 개당 비용이 사실상 0이다.
- 결정적으로 **증분이 정확하다**: 파일 1개 변경 → 액션 2개 재실행. 13,662개가 아니다. tree artifact였다면 전체가 무효화된다.
- Bazel 서버 힙: 13.6k 아티팩트에 **225 MB**. 10배 규모(약 140k 파일)로 외삽하면 약 2 GB — 관리 가능하지만 CI 머신 메모리 산정에 반영해야 한다.

⇒ 세밀한 액션 그래프는 비용이 아니라 **이점**이다. 이것이 tree artifact 대비 두 번째 근거다(첫 번째는 §2.2 A 절대 크기).

### 2.5 TypeScript 시맨틱은 cwd의 tsconfig에 묶인다 — 무음 파손

**측정 결과** (`@Injectable()` 데코레이터가 붙은 클래스의 `design:paramtypes`):

| cwd의 tsconfig | 결과 |
|---|---|
| `emitDecoratorMetadata: true` | `paramtypes: ["Dep"]` ✔ |
| 옵션 없음 | `undefined` — **에러도 경고도 없음** |
| tsconfig 자체가 없음 | `undefined` |
| **소스 파일 옆**에 `true` 설정 + cwd에는 없음 | `undefined` — **소스 옆 tsconfig는 무시된다** |

세 가지가 동시에 문제다.

1. **tsconfig가 어떤 룰의 입력으로도 선언되지 않으면 미선언 의존성이다.** 캐시 키에 안 들어가므로 증분 빌드가 틀린다.
2. **실패가 무음이다.** NestJS DI는 `paramtypes`가 `undefined`가 되면 런타임에 깨진다. 빌드는 초록불이다.
3. **cwd는 하나인데 모노레포는 패키지마다 tsconfig가 다르다.** `pkgs/api`(decorators)와 `pkgs/web`(jsx)를 한 cwd로 동시에 만족시킬 수 없다.

**`--tsconfig-override`는 Bun 1.4.2에서 고장나 있다.** 파일·디렉터리·절대경로 모든 형태에서:

```
Internal error: directory mismatch for directory ".../tsconfig.json", fd 3.
You don't need to do anything, but this indicates a bug.
→ paramtypes: undefined  (설정이 적용되지 않음)
```

역방향 테스트(cwd는 metadata 켜짐 + override로 꺼진 config 지정)에서도 `undefined`가 나왔다. ⇒ override는 cwd 설정을 **무력화만 하고 대상 설정을 로드하지 못한다.** 현재로선 사용 불가.

**해법 — 타겟마다 cwd를 자기 패키지 디렉터리로 둔다. (검증 완료)**

cwd는 어차피 액션/런처마다 정하는 값이다. 워크스페이스 루트 하나로 고정할 이유가 없다.

```
bazel-out/.../
  node_modules/           ← 조상 탐색으로 도달
  pkgs/api/  tsconfig.json (decorators)  main.ts   ← cwd = 여기
  pkgs/web/  tsconfig.json (jsx)         main.tsx  ← cwd = 여기
```

```
api paramtypes: [ "Dep" ]                                          ✔
web jsx: {"tag":"div","props":{"id":"x","children":"hi"}}          ✔
```

두 패키지가 서로 다른 TS 시맨틱으로 동시에 정상 동작하고, `reflect-metadata`는 루트 node_modules에서 조상 탐색으로 해석됐다.

⇒ **`tsconfig.json`은 모든 `bun_*` 룰의 명시적 입력이며, 런처는 타겟 패키지 디렉터리로 `cd` 한다.** §5의 "`ts_project` 불필요" 주장은 이 조건을 붙여야만 성립한다.

**미해결**: 한 프로세스가 패키지 경계를 넘는 소스를 import할 때 어느 tsconfig가 적용되는지, `extends` 상속 체인의 입력 선언, `paths`의 기준 경로 — 추가 적대 검증 요청 중.

### 2.6 패키지 단위 tree artifact는 성립한다 — 초안 결론 반증

**패키지당 tree artifact(내부 심볼릭 링크 0개) + tree artifact 바깥의 디렉터리 심볼릭 링크**를 만들어 실행:

```
node_modules/shared is: directory
중복 검사: find -L . -type f → 3 files        ← 중복 없음
id .../store/shared@1.0.0/node_modules/shared/index.js
same true  counter 3                          ← 모듈 동일성 보존
```

§2.2 A의 4.5× 중복도, §2.2 B의 사이클도 발생하지 않는다. §2.2 D의 "tree artifact였다면 `a === b`가 false"라는 서술도 **틀렸다** — 모듈 동일성은 tree artifact 여부가 아니라 **링크가 store 한 곳으로 수렴하는가**에만 달려 있다.

**액션 수 차이가 결정적이다.** 실제 isolated 설치(22패키지) 기준:

| 입도 | 링크/복사 액션 수 |
|---|---|
| 패키지 단위 (Bun이 실제로 만드는 링크) | **55** |
| 파일 단위 (§2.4 방식) | 3,252 복사 + 11,586 링크 ≈ **14,838** |

배율 약 **210×**. 1,500패키지 모노레포로 외삽하면 node_modules만 ~100만 액션(분석 ~75s, heap ~1.6GB, 사용자 코드 0줄 상태)이고, runfiles 트리도 타겟당 10만 엔트리가 되어 `bun_test` **하나당 17초**가 측정됐다. 타겟 200개면 CI가 죽는다.

**⇒ 1st-party·3rd-party 모두 패키지 단위로 통일한다.**

한때 "3rd-party는 패키지 단위, 1st-party는 파일 단위"로 나누려 했으나 **근거가 없었다.** 두 번의 실측이 이를 뒤집었다.

**(a) CAS 중복 제거는 입도와 무관하다.** 같은 설치(22패키지/3,252파일/17MB)를 원격 캐시에 올려 측정:

| 입도 | CAS 객체 | AC 엔트리 | 캐시 총 바이트 |
|---|---|---|---|
| 패키지 단위 (22 액션) | 3,133 | 22 | **7,156,448** |
| 파일 단위 (3,252 액션) | 9,571 | 3,248 | 9,301,616 |

"패키지 tree artifact가 통짜 블롭이 된다"는 내 우려는 **사실이 아니었다.** tree artifact는 REAPI Merkle 트리로 저장되므로 **중복 제거는 파일 내용 단위로 일어난다** (디스크상 고유 내용 3,069개 ≈ CAS 블롭 3,133개). 파일 단위는 액션당 Action/Command proto와 AC 엔트리만 늘려 **오버헤드 4.1배, 중복 제거 이득 0**이다.

**(b) §2.7이 컴파일을 패키지 단위로 강제하는 순간, 1st-party 파일 단위의 증분 이득이 사라진다.** 50패키지×100파일에 패키지별 컴파일을 붙이고 파일 1개 변경:

| 입도 | 콜드 액션 | 1파일 변경 시 | 시간 |
|---|---|---|---|
| 패키지 단위 | **51** | 1 스폰 | 0.36s |
| 파일 단위 + 패키지 컴파일 | 5,051 | 1 internal + 1 스폰 | 0.20s |

**0.16초를 벌자고 액션을 99배 늘린다.** 무효화 단위는 컴파일 액션이지 복사 액션이 아니므로, 앞단의 파일 단위 레이어가 주는 이득은 컴파일 액션에 흡수된다.

> **§2.4의 "0.3초 증분"은 비교 대상이 틀렸다.** *node_modules 전체 단일 아티팩트* 대비 측정이었지 *패키지 단위* 대비가 아니다. 올바른 비교는 위 표이고, 그 결과 §2.4의 "세밀한 액션 그래프는 이점"이라는 결론은 **철회한다.**

컴파일 단위가 거칠어지는 대가(파일 100개 패키지 하나를 고치면 100파일 재컴파일)는 Bazel 입도로 고칠 수 없고 **패키지를 쪼개서**만 고친다 — 이는 §2.7이 이미 강제하는 방향(tsconfig 경계 = 패키지 경계 = 컴파일 단위)과 일치한다.

### 2.7 패키지 경계를 넘는 import에서 §2.5 해법이 무너진다

§2.5의 "타겟마다 cwd를 자기 패키지로" 는 **격리 실행에서만** 성립한다. 모노레포의 표준 패턴(web이 api의 DTO/도메인 클래스를 import)에서:

```
기준선: cwd=pkgs/api, api 자기 자신        → paramtypes: [ "Dep" ]      ✔
문제:   cwd=pkgs/web, api 소스를 import    → paramtypes: undefined      ✗ 무음
```

**한 프로세스가 여러 패키지의 파일을 로드하는데 트랜스파일 시맨틱은 cwd 하나로 고정된다.** 소비하는 쪽 tsconfig가 제공하는 쪽 파일에 적용된다. 워크스페이스 심볼릭 링크로 소비해도 동일하다.

게다가 조회 기준이 옵션마다 다르다 (split-brain):

| 옵션 | 기준 |
|---|---|
| `paths` | **소스 파일** 기준 최근접 tsconfig |
| `jsx`, `emitDecoratorMetadata` | **cwd** 기준 tsconfig |

즉 "cwd 하나 = 설정 하나"라는 전제 자체가 Bun 내부에서 이미 깨져 있다. 설계로 우회할 수 있는 성질이 아니다.

**추가로 `extends`가 위험하다.**

```
extends: "../../node_modules/@cfg/base/tsconfig.json"   → paramtypes: [ Dep ]   ✔
extends: "@cfg/base/tsconfig.json"                      → undefined             ✗ 무음
extends: "@cfg/base"                                    → undefined             ✗ 무음
```

`@tsconfig/node20`이나 사내 `@company/tsconfig` 같은 **가장 흔한 공용 base 패턴이 Bun에서 동작하지 않는다.** tsc는 되고 bun은 안 되므로, `bun_types`(tsc) 타입체크는 통과하는데 런타임만 다르게 컴파일되는 최악의 조합이 된다. `references`도 Bun은 읽지 않는다.

**해법 — 패키지마다 자기 cwd에서 사전 컴파일한다. (검증 완료)**

```
cd pkgs/api && bun build ./svc.ts --outfile=svc.built.js --target=bun --packages=external
→ 산출물에 Reflect.metadata / design:paramtypes / __legacyDecorateClassTS 가 구워짐

cwd=pkgs/web 에서 사전 컴파일본 소비 → API paramtypes: [ "Dep" ]      ✔
```

컴파일 시점에 각 패키지가 **자기 cwd·자기 tsconfig로** 트랜스파일되므로, 소비자의 cwd가 무엇이든 시맨틱이 보존된다.

⇒ **`bun_library`는 소스를 복사만 하는 룰이 아니라 컴파일하는 룰이어야 한다.** "Bun이 TS를 직접 실행하므로 컴파일 단계가 없다"는 초안의 핵심 전제는 **단일 tsconfig 범위 안에서만 참이다.**

### 2.8 순환 의존 + `emitDecoratorMetadata` — Bazel과 무관한 Bun 런타임 결함

NestJS 모노레포에서 도메인 간 양방향 참조(주문↔배송, 화주↔운송사)는 일상적이다. 이 조합이 **Bun에서 터진다.**

```
A ↔ B 순환, @Inject(()=>B) + emitDecoratorMetadata: true
→ ReferenceError: Cannot access 'A' before initialization  (b.ts:6)
```

**근본 원인 (Bun이 생성한 코드로 확인):**

```js
__legacyMetadataTS("design:paramtypes", [
  typeof A === "undefined" ? Object : A     // ← 이 가드 자체가 던진다
])
```

ESM live binding에서 `A`는 **TDZ 상태의 `let` 바인딩**이다. 선언되지 않은 변수와 달리 **TDZ 바인딩에 `typeof`를 적용하면 예외가 발생**하므로, `undefined`를 막으려던 가드가 오히려 던진다. tsc의 CJS 출력은 `a_1.A` **프로퍼티 접근**이라 그냥 `undefined`가 되어 살아남는다.

**대조 실험:**

| 방식 | 결과 |
|---|---|
| Bun, `emitDecoratorMetadata: true` | ✗ ReferenceError |
| Bun, `emitDecoratorMetadata: false` | ✔ `circ ok: A->B` |
| Bun, `bun build --format=cjs` | ✗ 동일 실패 |
| Bun, `bun build` (esm 번들) | ✗ 동일 실패 |
| tsc + `module: commonjs` | ✔ `circ ok: A->B` |
| **Bun + 순환 쪽을 `import type`으로 강등** | **✔ `circ ok: A->B`** |

**⇒ 회피책은 있다. 그리고 그것은 NestJS의 표준 패턴이다.**

적대 리뷰는 "회피책은 tsc로 CJS 트랜스파일하는 것뿐"이라고 결론지었으나 **이는 과했다.** 순환의 한쪽을 `import type`으로 강등하면 Bun에서 정상 동작한다. 대가는 그 파라미터의 메타데이터가 실제 클래스 대신 `Object`가 되는 것인데:

```
B paramtypes: [ "Object" ]
```

**이건 결함이 아니라 정합적인 동작이다.** NestJS는 순환 의존에서 `design:paramtypes`로 토큰을 추론할 수 없으므로 애초에 `@Inject(forwardRef(() => B))`로 **토큰을 명시하도록 요구**한다. 즉 메타데이터가 `Object`인 것이 정상이고, 주입은 명시된 토큰으로 해결된다.

**대응 (코딩 규약 + 강제):**

1. 순환 쌍의 한쪽 import는 `import type`으로 강등한다.
2. 해당 주입 지점은 `@Inject(forwardRef(() => X))`로 토큰을 명시한다 (NestJS가 어차피 요구한다).
3. **`bun_types`(tsc) 타입체크에 이 규칙을 린트로 넣어 CI에서 강제**한다. 방치하면 `ReferenceError`가 런타임에야 드러난다.

**이 프로젝트에 유리한 조건**: 대상 저장소는 아직 애플리케이션 코드가 없는 greenfield다(문서만 존재). 기존 코드베이스를 고치는 문제가 아니라 **첫날부터 규약으로 채택하면 되는 문제**다.

**남는 리스크**: 이 제약을 모르는 3rd-party NestJS 라이브러리가 내부에 순환 + `emitDecoratorMetadata`를 갖고 있으면 우리가 고칠 수 없다. 사전 컴파일된 npm 배포본은 대개 CJS라 안전하지만, **TS 소스를 배포하는 패키지는 위험**하다. M4에서 실제 의존성으로 확인한다.

---

## 3. 설계 대안 비교

| | A. tree artifact node_modules | B. repo rule에서 `bun install` | C. 패키지별 repo + 파일 단위 링크 |
|---|---|---|---|
| hermetic | ○ | ○ (오프라인 캐시 필요) | ◎ (integrity 검증) |
| 중복 폭발 | **✗ 4.5×+** | ○ | ◎ 없음 |
| 사이클 안전 | **✗ 빌드 실패** | ○ | ◎ |
| 모듈 동일성 | **✗ 깨짐** | ○ | ◎ 검증됨 |
| 지연 페칭 | ✗ 전체 | ✗ 전체 | ◎ 타겟별 |
| 원격 실행 | ✗ | △ | ◎ |
| Starlark 복잡도 | 낮음 | 낮음 | **높음** |
| peer 해석 | Bun에 위임 | Bun에 위임 | **직접 구현 필요** |
| 비문서 내부 의존 | 없음 | **캐시 네이밍** | 없음 |

**초안의 선택(C)은 철회한다.** §2.3에서 검증했듯 §2.2 D의 링크 레이어 기법은 B안에도 그대로 적용 가능하며, 초안의 비교표는 "B는 이 기법을 못 쓴다"는 **논증되지 않은 가정** 위에서 B를 낮게 채점했다.

**채택: D안 (하이브리드) — 해석은 Bun, 바이트는 Bazel, 레이아웃은 우리.**

| 관심사 | 담당 | 근거 |
|---|---|---|
| 의존성/peer 해석 | `bun install` (오라클) | §2.3 — 재구현 0 |
| 바이트 페칭 | Bazel repo (지연 + integrity) | §2.1 B |
| node_modules 레이아웃 | 파일 단위 `ctx.actions.symlink` | §2.2 D |

C안 채택의 유일한 근거였던 "링크 레이어를 소유하려면 해석도 소유해야 한다"가 거짓이므로, 최대 리스크(semver + peer 재구현)를 지불할 이유가 없다.

### 3.1 rules_js를 fork하지 않는 이유

적대적 리뷰에서 "C안은 rules_js 재발명이니 fork하라"는 지적이 있었다. 실측으로 평가했다.

```
rules_js:  .bzl 146개 / 33,242줄
           pnpm을 언급하는 .bzl 파일: 60개 (41%)
           pnpm-lock 파서 자체: 390줄
           해석 관련 로직: npm_translate_lock_helpers 787 + state 546 + generate 646 = 약 2,000줄
```

- pnpm 시맨틱이 **파일의 41%에 퍼져 있다.** "390줄짜리 파서만 갈아끼우면 된다"는 규모가 아니다.
- 더 중요한 건, rules_js가 무겁게 지고 있는 약 2,000줄이 대부분 **lockfile에서 해석 그래프를 유도하는 로직**이다. D안은 그 그래프를 `bun install`에서 읽으므로 **이 부분이 통째로 불필요하다.**
- 33,242줄을 상속해서, 정작 우리에게 필요 없는 해석 엔진을 재사용하려고 60개 파일의 pnpm 가정과 싸우는 것은 순비용이다.

⇒ fork하지 않는다. 단, **`rules_js`의 링크 레이어 설계 결정(파일 단위 링크, copy_to_bin, cwd in bazel-out)은 그대로 차용한다.** 이건 이미 §2.2에서 독립적으로 재발견한 것이기도 하다. 참고 구현으로 계속 대조한다.

---

## 4. 아키텍처

```
┌─ Layer 0: 툴체인 ────────────────────────────────────────┐
│  bun_toolchain — 플랫폼별 bun 바이너리를 다운로드         │
│  toolchain_type //bun:toolchain_type                     │
└──────────────────────────────────────────────────────────┘
┌─ Layer 1: 페칭 (repository / module extension) ──────────┐
│  bun.lock 파싱 → 패키지당 repo 1개                        │
│    @bun__rxjs__7.8.2  (http_archive 상당, integrity 검증) │
│  BUILD 파일 자동 생성: filegroup + BunPackageInfo         │
└──────────────────────────────────────────────────────────┘
┌─ Layer 2: 링크 (분석 단계 Starlark) ─────────────────────┐
│  bun_link_packages — 파일 단위 ctx.actions.symlink로     │
│    node_modules/.store/<pkg>@<ver>/node_modules/<pkg>/   │
│    node_modules/<pkg> → .store/...                       │
│  ※ tree artifact 절대 사용 안 함                          │
└──────────────────────────────────────────────────────────┘
┌─ Layer 3: 사용자 룰 ─────────────────────────────────────┐
│  bun_library / bun_binary / bun_test / bun_bundle        │
│  bun_executable (--compile)                              │
└──────────────────────────────────────────────────────────┘
```

### 4.1 Layer 0 — 툴체인

```python
# MODULE.bazel
bun = use_extension("@rules_bun//bun:extensions.bzl", "bun")
bun.toolchain(version = "1.4.2")
use_repo(bun, "bun_toolchains")
register_toolchains("@bun_toolchains//:all")
```

- 플랫폼별 아카이브를 integrity로 고정. `exec_compatible_with`로 `linux/darwin/windows × x64/arm64`.
- `ToolchainInfo`에 `bun` 실행파일 + 버전 문자열을 담는다.
- 버전 문자열은 **액션 키에 포함**시킨다. Bun은 트랜스파일러이기도 하므로 버전이 바뀌면 산출물이 바뀐다.

### 4.2 Layer 1 — 페칭

module extension이 `bun.lock`을 읽고 패키지당 repo를 만든다.

```python
bun_deps = use_extension("@rules_bun//bun:extensions.bzl", "bun_deps")
bun_deps.lock(name = "npm", lockfile = "//:bun.lock", pnpm_style_isolation = True)
use_repo(bun_deps, "npm")
```

- URL 유도: `{registry}/{name}/-/{basename}-{version}.tgz` (§2.1 B에서 검증).
- `integrity`는 lockfile의 sha512를 그대로 사용 → Bazel의 `integrity` 인자에 직접 투입.
- `extension_metadata(reproducible = True)` — 네트워크 해석이 전혀 없으므로 (lockfile이 이미 완전 고정) MODULE.bazel.lock을 오염시키지 않는다.
- **지연 페칭**: repo는 실제로 참조될 때만 페치된다. 이게 C안의 큰 이점이다.

git/github 의존성은 별도 처리 (§7 미해결).

### 4.3 Layer 2 — 링크

Starlark에서 pnpm 스타일 store 레이아웃을 **직접** 계산한다.

```
node_modules/.store/<mangled>@<version>/node_modules/<name>/**   ← 실제 파일
node_modules/.store/<mangled>@<version>/node_modules/<dep>       ← 직접 의존성 심볼릭 링크
node_modules/<name>                                              ← 최상위 심볼릭 링크
node_modules/.bin/<bin>                                          ← bin 심볼릭 링크
```

**입도는 1st/3rd-party 모두 패키지 단위다 (§2.6).** 패키지당 tree artifact(내부 심볼릭 링크 0개) + tree artifact 바깥의 디렉터리 심볼릭 링크 1개. 파일 단위는 CAS 오버헤드 4.1배에 증분 이득 0이다.

- `<mangled>`: `@scope/name` → `@scope+name`.
- **각 store 디렉터리에 그 패키지의 직접 의존성을 전부 링크**한다 (§2.2 E — 안 하면 phantom dependency가 통과한다).
- peer 의존성 충돌로 같은 패키지의 인스턴스가 갈리는 경우, Bun처럼 peer 집합 해시를 디렉터리 이름에 붙인다. **해시 함수는 Bun과 같을 필요가 없다** — 우리가 링크 레이어를 소유하므로 우리 해시를 쓰면 된다. §2.1 D의 제약은 "Bun의 레이아웃을 복제하려 할 때"만 문제가 된다. 복제하지 않는다.

### 4.4 Layer 3 — 사용자 룰

**`BunInfo` provider**

```python
BunInfo = provider(fields = {
    "sources":       "depset[File] — bazel-out의 실제 파일",
    "types":         "depset[File] — .d.ts",
    "npm_deps":      "depset[BunPackageInfo]",
    "transitive_sources": "depset[File]",
    "package_name":  "string 또는 None",
})
```

`rules_js`의 `JsInfo`와 달리 `declaration`/`transpilation` 출력 그룹을 분리하지 않는다. Bun이 실행 시점에 TS를 직접 읽기 때문에 트랜스파일 산출물이 애초에 없다.

**`bun_library`** — **패키지를 자기 cwd·자기 tsconfig로 컴파일한다** (§2.7). `tsconfig`는 명시적 attr이며 `extends` 체인의 대상 파일도 입력으로 선언한다. 산출물은 bazel-out의 실제 파일(§2.2 D). 초안의 "복사만 하는 저비용 룰"은 철회.

**`bun_binary`** — 런처 스크립트 + runfiles. 런처는 반드시:
1. cwd를 runfiles 안 bazel-out 대응 디렉터리로 이동
2. `bun --no-install` 로 실행 (§2.1 E)
3. `bunfig.toml`을 명시적으로 지정하거나 무력화 — 사용자 홈의 `~/.bunfig.toml`이 새어들어오면 hermeticity가 깨진다

**`bun_test`** — `bun_binary` + 테스트 계약:
- `--reporter=junit --reporter-outfile=$XML_OUTPUT_FILE`
- `TEST_TMPDIR` → `HOME`, `BUN_INSTALL_CACHE_DIR`을 강제로 그 아래로
- `--test-name-pattern`에 `$TESTBRIDGE_TEST_ONLY` 연결
- **샤딩: Bun 내장 `--shard=$((TEST_SHARD_INDEX+1))/$TEST_TOTAL_SHARDS`를 쓴다** (§2.1 H). `TEST_SHARD_STATUS_FILE`은 touch. `--timings`로 시간 균형까지 얻는다. (초안의 수동 파일 분할은 철회)
- 커버리지: `--coverage --coverage-reporter=lcov` → `COVERAGE_OUTPUT_FILE`로 이동.
  **파일 부재가 정상 케이스**이고(§2.1 G), `SF:` 경로를 워크스페이스 상대로 **재작성**해야 한다.
- **스냅샷**: `toMatchSnapshot()`은 테스트 파일 옆 `__snapshots__/`에 쓰며 위치 변경 플래그가 없다. 읽기 전용 샌드박스에서는 **일치해도 실패**한다. 대응: 스냅샷 디렉터리를 쓰기 가능 경로로 복사 후 실행하고, 갱신은 `--update-snapshots`를 쓰는 별도 `bun_snapshot_update` 타겟(`bazel run`)으로 분리해 소스 트리에 다시 쓴다.

**`bun_bundle`** — `bun build`. `--outdir`은 `declare_directory`를 쓰고 싶어지지만, **content hash 파일명 때문에 출력이 예측 불가**하다. 두 모드로 나눈다:
- `naming = "[name].[ext]"` + splitting 없음 → 개별 `declare_file`, 예측 가능, 캐시 친화적 (기본값)
- splitting/hash 필요 시 → `declare_directory` 허용 (심볼릭 링크가 없으므로 §2.2 A 문제 없음)

**`bun_executable`** — `bun build --compile`. `--target=bun-<os>-<arch>`를 Bazel 타겟 플랫폼에서 유도. `--outdir` 미지원이므로 `--outfile` 단일 출력.

---

## 5. rules_js / rules_ts 대체 매핑

| rules_js / rules_ts | rules_bun | 비고 |
|---|---|---|
| `npm_translate_lock` | `bun_deps.lock()` | pnpm-lock 대신 bun.lock |
| `npm_link_all_packages` | `bun_link_packages` | 파일 단위 심볼릭 링크 |
| `js_library` | `bun_library` | |
| `js_binary` | `bun_binary` | |
| `js_test` | `bun_test` | JUnit 네이티브 |
| `js_run_binary` | `bun_run` | |
| `ts_project` (트랜스파일) | **`bun_library`가 수행** | §2.7 — 컴파일 단계는 **필수**다 |
| `ts_project` (타입체크/선언) | `bun_types` | `tsc --noEmit` / `--emitDeclarationOnly` |
| `copy_to_bin` | `bun_library`에 내장 | §2.2 D 때문에 항상 필요 |
| esbuild 룰 | `bun_bundle` | |

**초안의 "`ts_project` 불필요"는 철회한다.**

§2.7에서 반증됐다. Bun이 TS를 직접 실행하는 것은 사실이지만, **트랜스파일 시맨틱이 프로세스 단위(cwd)로 고정되므로 여러 패키지가 한 프로세스에 로드되는 순간 무너진다.** 모노레포에서 이건 예외가 아니라 표준이다.

따라서 `bun_library`는 **패키지별 컴파일 룰**이다. `tsc` 대신 `bun build`를 쓰고, 각 패키지를 자기 cwd·자기 tsconfig로 컴파일해 시맨틱을 산출물에 굽는다. 이름만 다를 뿐 `ts_project`가 하는 일과 같은 자리다.

**Bun이 대체하지 못하는 것 (그대로 유지):**

- **타입 체크.** Bun은 타입을 검사하지 않고 지운다. `bun_types`가 `typescript` 패키지를 툴로 받아 담당하며, `_validation` output group에 넣어 빌드를 막지 않고 병렬로 돌린다.
- **`extends` 패키지명 참조.** §2.7 — Bun이 무음으로 무시한다. 룰셋이 **상대경로로 정규화**하거나 금지해야 한다. 방치하면 tsc는 통과하고 런타임만 다르게 컴파일된다.

---

## 6. 핵심 난제와 대응

| 난제 | 대응 |
|---|---|
| **라이프사이클 스크립트** | **초안의 "allowlist로 별도 액션" 모델은 불충분하다.** §6.1 참조. |
| **네이티브 애드온** (`.node`) | 플랫폼별 optional dependency를 `select()`로 해석. lockfile의 `os`/`cpu` 메타(§2.1 A)를 Bazel 제약으로 번역. |
| **git 의존성** | lockfile integrity 사용 불가(§2.1 I). §6.2 참조. |
| **`overrides` 전파** | lockfile의 `meta.dependencies`는 **원본 매니페스트**이지 해석된 엣지가 아니다. overrides를 걸면 top-level 해석은 바뀌지만 meta는 그대로라, meta를 그대로 링크하면 **lockfile에 없는 버전**을 참조한다. → D안에서는 해석 그래프를 `bun install` 결과에서 읽으므로 자동 해소된다(§2.3). meta는 링크 근거로 쓰지 않는다. |
| **미충족 peer 자동 추가** | Bun은 optionalPeers가 아닌 미충족 peer를 트리에 자동 추가한다. lockfile만으로는 재현 불가. → 동일하게 오라클로 해소. |
| **자동 설치 구멍** | 모든 액션에 `--no-install`. 린트 규칙으로 강제. |
| **`~/.bunfig.toml` 누수** | 액션 env를 `use_default_shell_env = False`로 고정하고 `HOME`을 샌드박스 내부로. `--config`로 생성한 bunfig 명시. |
| **realpath 탈출** | store는 실제 파일, cwd는 bazel-out (§2.2 D). |
| **모듈 중복 인스턴스** | 단일 store 파일로 realpath 수렴 (§2.2 D 검증). |
| **sourcemap 경로** | realpath가 bazel-out 절대경로로 나옴. `--sourcemap` 산출물에 경로 재작성 후처리 필요. |
| **워커** | `bun_types`(tsc)는 persistent worker 후보. Bun 자체는 시작이 빨라(수 ms) 워커 이득이 작다. 1차 범위 밖. |
| **원격 실행** | **초안의 단언을 철회한다.** `ctx.actions.symlink(target_file=)`의 출력은 **execroot 절대경로** 심볼릭 링크(`/home/.../execroot/_main/bazel-out/...`)라 재배치 불가고, symlink 액션은 `internal`이라 **원격 실행 대상이 될 수 없다** — 전부 로컬 JVM에서 처리된다. §2.6의 패키지 단위 입도가 이 비용을 210× 줄이는 것이 사실상의 대응이며, 원격 실행 호환은 M7에서 **검증 대상**이지 전제가 아니다. |
| **exec / target 설정 분리** | §6.3 — "설정 무관하게 공유"는 **불가능하며 철회한다.** |
| **크로스 컴파일** | `bun build --compile`은 `--compile-executable-path=<path>`로 다운로드 없이 대상 플랫폼 bun을 지정할 수 있다. 이것이 hermetic 크로스 컴파일의 유일한 경로다. 툴체인이 **target 플랫폼용 bun도** 받아야 한다(§4.1에 누락돼 있었다). |
| **컴파일된 바이너리의 런타임 hermeticity** | `--compile-autoload-dotenv` / `--compile-autoload-bunfig`가 **기본 true**라, 컴파일된 바이너리가 *실행 시점에* `.env`/`bunfig.toml`을 읽는다. §6이 막은 것은 빌드 시점뿐이므로 둘 다 명시적으로 끈다. |

### 6.1 라이프사이클 스크립트 — 초안 모델의 붕괴

초안은 "3rd-party 패키지의 postinstall 산출물을 불변으로 보고 store에 커밋"한다고 썼다. 실제 패키지로 검증하니 **세 가지 서로 다른 이유로 무너진다.**

**(a) 네트워크에서 바이너리를 받는 것** — `better-sqlite3`
`install: "prebuild-install || node-gyp rebuild"`, tarball에 `.node` 없음. `prebuild-install`은 **설치 시점에 GitHub Releases에서 바이너리를 받는다.** 그 URL도 integrity도 lockfile에 없다.
대안인 `node-gyp`는 C++ 툴체인 + Python + **node**를 요구한다 — §1 목표 1("Node.js 제거")과 정면충돌.
→ **대응**: 이런 패키지는 사전 빌드된 `.node`를 `http_file`로 **명시적으로 핀**해 별도 Bazel 타겟으로 만들고, 링크 시 주입한다. 자동화 불가, 패키지별 수작업. 목록을 문서화하고 CI에서 목록 밖 패키지가 스크립트를 요구하면 **빌드 실패**시킨다.

**(b) 1st-party 입력을 읽어 코드를 생성하는 것** — `@prisma/client`
postinstall이 **우리 `schema.prisma`를 읽어 node_modules 안에 코드를 생성**한다. `preinstall`도 있다(초안은 postinstall만 다뤘다). "3rd-party는 불변"이라는 전제가 성립하지 않는다.
→ **대응**: 라이프사이클 스크립트가 아니라 **1급 빌드 룰**(`prisma_generate`)로 승격한다. 생성물은 store가 아니라 별도 아티팩트로 두고 `bun_library`처럼 취급한다. 이게 옳은 모델이며, npm 라이프사이클로 흉내내면 안 된다.

**(c) 로컬과 Bazel의 기본값이 갈리는 것**
Bun에는 **문서화되지 않은 기본 trusted 목록**이 있다. `esbuild`/`sharp`/`prisma`/`better-sqlite3`/`@swc/core` 중 `bun pm untrusted`에 뜬 것은 `@swc/core` 하나뿐이었다. 로컬 `bun install`은 스크립트를 돌리고 Bazel은 `--ignore-scripts`이므로 **"로컬에선 되는데"** 가 구조적으로 발생한다.
→ **대응**: `bun pm default-trusted` 출력을 룰셋에 스냅샷해 두고, 로컬과 Bazel의 차이를 진단 명령으로 노출한다.

### 6.2 git 의존성

§2.1 I에서 lockfile integrity가 tarball과 불일치함이 확인됐으므로 세 가지 선택지뿐이다.

1. **금지한다** (기본값). `bun.lock`에 git 의존성이 있으면 번역 단계에서 에러. 대부분의 조직에 이게 옳다.
2. **integrity 없이 커밋 SHA로 고정**해 `git_repository`로 받는다. 커밋 SHA가 불변성을 주므로 실무상 충분하나, Bun이 만든 바이트와 다를 수 있다.
3. **오라클 경로로 우회**: `bun install`이 만든 결과를 그대로 vendor한다.

1을 기본으로, 2를 opt-in으로 제공한다.

### 6.3 exec / target 설정 분리 — 링크 레이어는 복제된다

같은 링크 타겟을 `target_dep`(기본)과 `exec_dep`(`cfg="exec"`) 양쪽에서 참조해 측정:

```
소스 20개 → INFO: 42 processes (20 target + 20 exec + 소비자 + internal)
bazel-out/k8-fastbuild/bin/.../nm/f0.js
bazel-out/k8-opt-exec/bin/.../nm/f0.js     ← 완전 별개 사본
```

**정확히 2배로 복제된다.** `ctx.actions.*`의 출력은 정의상 configured target에 귀속되고, Starlark에는 exec 설정을 지워 정규 설정으로 되돌리는 transition이 없다. 앞선 초안의 "링크는 설정 무관하게 공유되도록 설계한다"는 **불가능하므로 철회한다.**

가능한 대응, 권장 순서대로:

1. **npm 패키지를 exec transition으로 끌지 않는다 (기본 전략).** 데이터인 패키지는 `cfg="target"`으로 두고 exec 설정에는 *실행 파일인 툴만* 넣는다. `bun_types`(tsc)는 exec에서 돌며 `typescript` 패키지를 필요로 하므로 **툴 전용 node_modules를 별도 타겟으로 분리**한다.
2. **2배를 받아들인다.** 패키지 단위이므로 22패키지 → 44액션으로 감당 가능하다. **파일 단위였다면 이것이 치명타였다** (3,252 → 6,504, 실규모에선 수백만). §2.6의 입도 통일이 여기서도 결정적이다.
3. **repository rule 산출물로 만든다.** repo 출력은 소스 취급이라 **설정 독립이고 사본이 1개**다.

> **이것이 탈출구 B(`bun install` in repo rule)를 남겨두는 진짜 이유다.** 초안이 적은 이유("네이티브 빌드/복잡한 라이프사이클 스크립트")보다 훨씬 중요하다. B는 **유일하게 설정 독립인 설계**다.

### 6.4 `--remote_download_minimal`에서의 끊어진 심볼릭 링크

캐시 히트 상태에서 `bazel build --remote_download_minimal`을 돌리면 디스크의 `bazel-bin/.../node_modules` 링크가 **대상 없이 남는다** (파일 단위·패키지 단위 모두 동일). 빌드 자체는 정상이다:

- 소비자 액션이 있으면 Bazel이 프리페치한다 → 정상
- `bazel run`도 runfiles를 프리페치한다 → 정상
- `--remote_download_toplevel`이면 링크가 해소된다

**깨지는 것은 Bazel 밖에서 node_modules를 직접 들여다보는 워크플로다** — IDE, 또는 `bazel-bin`에서 `bun run`을 수동 실행하는 경우. 규칙으로 못 박는다: **`bun_binary` 런처는 Bazel 액션/runfiles 밖에서 node_modules를 참조하지 않는다.**

---

## 7. 미해결 사항 / 리스크

**리스크 (핵심 가정 — 무너지면 설계 변경)**

1. **Windows 심볼릭 링크.** 채택안의 **핵심 메커니즘 자체가 파일 단위 심볼릭 링크**다. Windows에서 생성 권한/개발자 모드 요구나 260자 경로 제한이 걸리면 설계 근간이 흔들린다. "미검증 디테일"이 아니라 **핵심 가정에 대한 미검증 리스크**다. → 목표 플랫폼에서 Windows를 뺄지 M1에서 결정한다.
2. **모듈 동일성은 단일 계층에서만 검증됐다** (§2.2 D). NestJS DI 전체가 해결됐다는 결론은 **아직 가설**이며 M4가 진짜 검증이다. 그 전까지 채택안은 미검증 가설 위에 서 있다.
3. **Bun 캐시 네이밍은 비문서 내부 구현이고, 스킴이 종류마다 다르다**(§2.1 C). 오라클 경로가 여기 의존한다. Bun 버전을 핀하고 CI 검증 테스트를 돌린다.
4. **중첩 키 파싱 계약이 문서화돼 있지 않다.** 실제로 다단계이며(`"@adv/web/@nestjs/common/rxjs"`) 세그먼트 자체가 `/`를 포함하는 스코프명이라 단순 split이 불가능하다. `@` 접두 규칙을 알아야 분해되는데 이는 문서화된 계약이 아니다.

5. **순환 의존 + `emitDecoratorMetadata`가 Bun에서 터진다** (§2.8). 회피책(`import type` + 명시 토큰)은 있고 greenfield라 규약화 가능하지만, **3rd-party 라이브러리가 위반하면 우리가 고칠 수 없다.** M0의 검증 대상.

**리스크 (해소됨 / 반증됨 — 기록용)**

- ~~peer 해석 재구현~~ → §2.3 오라클로 제거. 초안 최대 리스크였다.
- ~~증폭률 초선형 가정~~ → §2.2 A에서 반증. 상수 ~4×.
- ~~"tree artifact 설계 폐기"~~ → §2.6에서 반증. 내부 심볼릭 링크만 문제였다.
- ~~"파일 단위가 증분에 유리"~~ → §2.6에서 반증. 0.16초에 액션 99배.
- ~~"패키지 tree artifact는 통짜 CAS 블롭"~~ → §2.6에서 반증. Merkle 트리라 입도 무관.
- ~~"링크 레이어를 설정 무관하게 공유"~~ → §6.3에서 반증. 정확히 2배 복제된다.

**미검증**

- `.npmrc` / 스코프별 레지스트리 인증 토큰
- `patchedDependencies` — 지정 시에도 integrity는 **패치 전** 값이라, 패치 후 바이트를 Bun과 일치시킬 보증이 없다
- macOS / 원격 실행에서 §2.2 D·§2.5 결과의 재현
- `bun build --compile` 재현성 (Bun에서 가장 실험적인 기능이라 업스트림 안정성에 종속)
- 패키지 경계를 넘는 import에서의 tsconfig 적용, `extends` 체인의 입력 선언, `paths` 기준 경로 (§2.5)

**유지보수 리스크 (Bun 업그레이드마다 깨질 수 있는 지점)**

| 지점 | 결합 대상 |
|---|---|
| lockfile 파서 | 튜플 위치/타입 — `lockfileVersion` 상승 시 재작성 |
| 캐시 네이밍 | 비문서 내부 구현, 종류별 상이 |
| store 디렉터리명 (peer 해시) | 오라클이 읽는 대상 |
| `--tsconfig-override` | **현재 고장**. 고쳐지면 §2.5 해법을 단순화할 수 있다 |
| `bun build --compile` | 실험적 |

**의도적으로 남기는 것**

- 타입 체크는 `tsc`. Bun으로 대체 불가.
- `bun_bundle`의 hash 파일명 모드는 tree artifact를 쓴다 (심볼릭 링크가 없어 안전).

---

## 8. 검증 계획

각 마일스톤은 **실행 가능한 테스트**로 끝난다.

| M | 범위 | 통과 기준 |
|---|---|---|
| M1 | 툴체인 | 3개 플랫폼에서 `bazel run @bun//:bun -- --version` |
| M2 | 페칭 | 200+ 패키지 lockfile을 번역, 모든 integrity 검증 통과, 네트워크 차단 상태에서 재빌드 성공 |
| M3 | 링크 | **(인스턴스, dep이름) → 인스턴스 엣지 집합**이 `bun install --linker isolated`와 완전 일치 |
| M4 | 실행 | NestJS 앱 부팅. **DI 컨테이너가 뜨는 것이 §2.2 D·§2.5의 진짜 검증이다** |
| M5 | 테스트 | JUnit XML + lcov 전달, `--shard` 동작, **스냅샷 테스트 통과** |
| M6 | 번들/실행파일 | `bun build` / `--compile` 산출물 재현성 |
| M7 | 원격 | 원격 캐시 + 원격 실행에서 M1~M6 전부 재현 |

> **M3의 통과 기준은 초안에서 바꿨다.** 초안은 "패키지→버전 매핑 일치"였으나 이 기준은 **잡아야 할 실패를 놓친다.** 적대 검증에서 나온 반례: 같은 `@nestjs/common@10.4.15`가 서로 다른 peer 집합으로 **인스턴스 2개**로 갈리는 경우
> ```
> @nestjs+common@10.4.15+69eecedea3c78715 → rxjs@7.5.0, reflect-metadata@0.2.2
> @nestjs+common@10.4.15+766b24fd5eddd0a7 → rxjs@7.8.2, reflect-metadata@0.1.14
> ```
> 두 인스턴스 모두 버전 맵으로는 `@nestjs/common → 10.4.15`다. **peer 엣지를 서로 반대로 링크해도 M3은 초록불**이고 rxjs `instanceof`/오퍼레이터만 런타임에 조용히 깨진다. 비교 단위는 버전 맵이 아니라 엣지 집합이어야 한다.

**가장 먼저 해야 할 일 (두 차례 수정됨).**

초안은 "M3 differential test"였다. 적대 검증을 거치며 순서가 두 번 바뀌었다.

1. **M0 — NestJS 실행 가능성 스파이크 (Bazel 없이).** 순수 Bun으로 순환 의존 + `emitDecoratorMetadata` + 실제 NestJS DI 컨테이너를 부팅시킨다. §2.8의 `import type` 규약이 실제 NestJS에서 성립하는지, 3rd-party 라이브러리가 이 제약을 위반하지 않는지 확인한다.
   **이게 실패하면 룰셋 설계 전체가 무의미하다.** Bazel 코드를 한 줄도 쓰기 전에 확인한다.
2. **M4' — §2.7 사전 컴파일 + §2.2 D 링크로 그 앱을 Bazel에서 부팅.** 모듈 동일성과 tsconfig 시맨틱이 동시에 걸리는 지점.
3. M3 (엣지 집합 differential).
4. M1에서 **Windows를 목표 플랫폼에 유지할지 결정** (리스크 #1).

> 초안이 1순위로 꼽았던 M3는 **4순위로 내려간다.** M3는 "설계가 맞게 도는지"를 보지만, M0/M4'는 "이 설계가 성립하는지"를 본다. 후자가 먼저다.

---

## 부록 A: 실험 재현 방법

모든 실험은 `bun 1.4.2` / `bazel 9.2.0` / Linux x64에서 수행.

- §2.1 A — `bun install --lockfile-only --save-text-lockfile` 후 `bun.lock` 관찰
- §2.1 B — `curl -sL <url> | openssl dgst -sha512 -binary | base64`
- §2.1 C — 글로벌 캐시에서 `<name>@<ver>@@@1` 디렉터리 복사 → `BUN_INSTALL_CACHE_DIR=... bun install --offline --frozen-lockfile`
- §2.1 D — `bun install --linker isolated` 후 `ls node_modules/.bun`
- §2.2 A — `find node_modules -type f | wc -l` vs `find -L node_modules -type f | wc -l`
- §2.2 B — `declare_directory` 액션에서 `ln -s .. dir/up` 생성
- §2.2 D — store 파일은 `cp`, 링크 레이어는 `ctx.actions.symlink`, cwd = bazel-out
