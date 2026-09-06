# Bazel 범용 설정·훅·CI 생태계 조사

대상: 다언어 MSA 모노레포 설계자. 조사일: 2026-09-06.

## 결론

Lefthook을 Bazel 대표 조합처럼 먼저 추천한 것은 근거가 부족했다. 공식 권장, 공개 저장소 채택, 신흥 대안, 이 프로젝트에 대한 권고를 분리해야 한다.

- 기반: Bazelisk와 버전 고정, Bzlmod, lockfile, 공통 bazelrc, buildifier.
- 훅: 다언어에서는 pre-commit을 보수적 출발점으로 검토. Node 기반 개발환경이 이미 필수라면 Husky도 타당.
- 신흥 대안: prek. 기존 pre-commit 설정 호환성과 실행환경을 실제 검증한 뒤 선택.
- 커밋 검사: commitlint, Python Commitizen, gitlint 중 정책에 맞는 하나. 훅 관리자와 별개다.
- CI: 동일 검사를 필수 체크로 강제. 공유 캐시와 원격 실행은 규모·병목에 따라 추가.

위 권고는 아래 기능·채택 증거에 대한 분석이지 시장 점유율 순위가 아니다. 사내 비공개 설정까지 전수 파악하거나 “가장 많이 쓰는 조합”을 증명하지 못했다.

## 1. 공식 기반과 팀별 선택

| 영역 | 근거 있는 출발점 | 장점 | 비용·주의 |
|---|---|---|---|
| Bazel 설치 | Bazelisk + .bazelversion | 개발자·CI의 Bazel 버전 통일 | 최신 버전 자동 추종보다 호환 릴리스 고정·업그레이드 검증 |
| 외부 의존성 | MODULE.bazel + MODULE.bazel.lock | 모듈 의존성 해석과 공통 잠금 | 언어 패키지·toolchain 정책까지 자동 통일되는 것은 아님 |
| 실행 옵션 | .bazelrc | CI·로컬·플랫폼 설정 공유 | 개인 설정과 비밀정보를 공통 파일에 섞지 않기 |
| BUILD/Starlark 품질 | buildifier | 포맷과 Bazel 관련 lint | 제품 소스용 ESLint/Ruff 등의 대체재는 아님 |
| 의존성 경계 | visibility·명시적 deps | 서비스·라이브러리 경계의 빌드 수준 검증 | 런타임 통신·API 호환성은 별도 검증 |

Bazel 공식은 Bazelisk를 권장하고 .bazelversion의 버전관리를 안내한다. Bzlmod는 WORKSPACE를 대체하는 방향이며 신규 설정은 오래된 WORKSPACE 예제를 기준으로 삼지 않는다. Lockfile도 버전관리가 권장된다. [Bazelisk 공식](https://bazel.build/install/bazelisk), [Bzlmod 이행](https://bazel.build/external/migration), [Lockfile](https://bazel.build/external/lockfile)

공통 옵션의 동작은 bazelrc 공식 문서, 포맷·lint는 buildifier 문서, 경계는 visibility 문서를 기준으로 한다. “Bazel 공식 도구”와 “공식 문서에서 소개하는 외부 도구”는 구분한다. [bazelrc](https://bazel.build/run/bazelrc), [buildifier](https://github.com/bazelbuild/buildtools/blob/main/buildifier/README.md), [visibility](https://bazel.build/concepts/visibility)

## 2. Git 훅 관리자 비교

| 후보 | 강점 | 약점·추가 비용 | 판단 |
|---|---|---|---|
| pre-commit | 언어별 도구 환경·파일 선택·버전 고정·CI 재사용 | Python 실행환경, 최초 도구 설치 시간; Bazel과 도구 버전 중복 관리 가능 | 공개 Bazel 채택 증거가 있는 보수적 다언어 후보 |
| prek | Rust 단일 실행파일, pre-commit YAML 호환, workspace 지원 | 실행 도구 자체의 런타임은 여전히 필요; 전용 기능은 pre-commit 역호환 안 됨 | 신흥 대안으로 평가, Bazel 표준이라고 부르지 않기 |
| Husky | npm prepare와 자연스러운 설치, Git 기본 훅 구조, POSIX shell | 설치가 JS 도구체인에 연결; 파일 선택·언어별 환경·병렬화는 별도 구성 | JS/TS 환경이 이미 필수라면 합리적 |
| Lefthook | YAML 작업·glob·staged files·병렬 실행, 다양한 설치 경로 | 검사 실행환경을 별도로 제공해야 함; Bazel 대표 채택 근거 부족 | 기존 팀 선호·병렬 작업 수요가 있으면 선택 |
| Git core.hooksPath | 외부 관리자 없이 버전관리 훅 디렉터리 사용 | 설치·업데이트·파일선택·OS 차이를 자체 스크립트로 유지 | 검사 수가 적고 bootstrap을 관리할 때 가능 |
| 로컬 훅 없음 | 개발자 설치 부담 없음; CI에서 일관된 판정 | 실패 피드백이 늦음 | CI 필수 체크와 빠른 피드백이 확보되면 가능 |

기능 근거: [pre-commit](https://pre-commit.com/), [prek](https://prek.j178.dev/), [prek 호환성](https://prek.j178.dev/compatibility/), [Husky](https://typicode.github.io/husky/), [Lefthook](https://lefthook.dev/), [Git hooks](https://git-scm.com/docs/githooks). 마지막 열은 분석이다. 도구 자체 실행속도와 실제 lint·test 완료시간은 다르며 이 프로젝트에서 벤치마크하지 않았다.

### 실제 채택 증거

- buildtools의 공개 설정은 pre-commit으로 buildifier와 buildifier-lint를 실행한다. 이것은 Bazel 생태계 내 채택 사례이지 전체 Bazel 공식 지정이 아니다. [실제 설정](https://raw.githubusercontent.com/bazelbuild/buildtools/main/.pre-commit-config.yaml)
- bazel-contrib의 rules-template은 pre-commit·buildifier·GitHub Actions를 포함한다. 단, 애플리케이션 모노레포가 아니라 ruleset 개발용 템플릿이다. [템플릿](https://github.com/bazel-contrib/rules-template)
- bazel-lib는 pre-commit·buildifier에 Python Commitizen의 commit-msg 검사와 기타 파일 검사를 결합한다. [실제 설정](https://raw.githubusercontent.com/bazel-contrib/bazel-lib/main/.pre-commit-config.yaml)
- Angular의 package.json에는 Husky 설치와 Bazelisk test가 공존한다. 따라서 “Bazel이면 Husky를 쓰지 않는다”는 주장은 틀리다. Angular를 Husky+commitlint의 사례라고 확대하지 않는다. [실제 package.json](https://raw.githubusercontent.com/angular/angular/main/package.json)
- Commitizen 자체 가이드가 prek/pre-commit 통합을 안내한다. 이는 신흥 도구를 검토할 근거이지 Bazel 점유율 증거가 아니다. [자동 검사 가이드](https://commitizen-tools.github.io/commitizen/tutorials/auto_check/)

Husky 공식의 GitHub 150만+ 프로젝트 수치는 전체 생태계 제공자 주장이다. Bazel 프로젝트 수나 타 도구와 동일한 분모의 통계가 아니다. Lefthook 대표 Bazel 사례를 이번 조사에서 확보하지 못한 것은 “아무도 사용하지 않는다”는 증거가 아니다.

## 3. 커밋 메시지 검사기는 독립 선택

| 후보 | 적합한 요구 | 주의 |
|---|---|---|
| commitlint | Conventional Commits, JS 공유 규칙·플러그인 | Node 필요. Husky 전용이 아니며 어떤 훅에서든 호출 가능 |
| Python Commitizen | 메시지 검사·작성 보조·버전 및 changelog | JS의 동명 Commitizen과 구분. 검사만 필요하면 기능이 많을 수 있음 |
| gitlint | 제목·본문·사용자 정의 규칙 중심 | Conventional Commits 정책을 원하면 해당 규칙을 명시 |
| PR 제목 검사 | squash-only에서 최종 커밋 제목 규칙 보장 | PR 제목을 최종 squash 제목으로 반영하는 병합 정책이 전제 |

근거: [commitlint 로컬 가이드](https://commitlint.js.org/guides/local-setup), [Python Commitizen](https://commitizen-tools.github.io/commitizen/), [gitlint](https://jorisroovers.com/gitlint/latest/), [semantic PR action](https://github.com/amannn/action-semantic-pull-request).

권고: commitlint를 유지하고 싶다면 훅 관리자만 비교하면 된다. pre-commit을 택했다고 반드시 Commitizen으로 바꿀 이유는 없다. 반대로 Node를 오직 commitlint 때문에 들여오는 상황이면 Python 검사기를 검토할 수 있다.

메시지는 pre-commit이 아닌 commit-msg 단계에서 검사한다. 로컬 훅은 우회할 수 있으므로 CI 필수 검사가 최종 판정이어야 한다. squash 정책이면 모든 임시 커밋과 최종 제목을 이중 강제할 필요가 있는지 먼저 결정한다. [Git hooks](https://git-scm.com/docs/githooks), [commitlint](https://commitlint.js.org/guides/local-setup)

## 4. Bazel 개발 품질·반복작업

| 도구 | 역할·장점 | 한계·적용 기준 |
|---|---|---|
| Gazelle | BUILD 생성·갱신; Go·protobuf 기본 지원, 언어 확장 | 모든 언어·동적 의존성을 자동 해결하지 않음 |
| rules_lint | 기존 타깃에 aspect로 lint 적용, Bazel 캐시·원격 실행 활용 | 소스가 그래프에 있어야 함. formatter 동작과 lint 동작 구분 |
| ibazel | 소스 변경 시 Bazel 타깃 재실행 | 각 개발 서버의 hot reload 의미까지 동일하게 만들지는 않음 |
| IDE 통합 | Bazel 타깃·Starlark와 IDE 연결 | 언어·IDE·ruleset별 실제 코드 탐색과 디버깅 검증 필요 |
| Renovate | Bazel 버전·Bzlmod 의존성 갱신 PR | 호환 조합·lockfile 재생성·CI 승인 정책은 팀 책임 |

근거: [Gazelle](https://github.com/bazel-contrib/bazel-gazelle), [rules_lint](https://github.com/aspect-build/rules_lint), [ibazel](https://github.com/bazelbuild/bazel-watcher), [IDE 공식](https://bazel.build/install/ide), [Renovate Bzlmod](https://docs.renovatebot.com/modules/manager/bazel-module/), [Renovate Bazelisk](https://docs.renovatebot.com/modules/manager/bazelisk/).

언어별 ruleset은 별도 선택이다. 공식 문서도 rules_go·rules_python·rules_jvm_external 등의 Bzlmod 통합을 소개한다. JS/TS에는 Aspect rules_js/rules_ts 계열, Python에는 rules_python과 별도 rules_py 대안이 있다. 이를 전부 “Bazel 본체 공식 지원”이라고 묶지 않는다. 이 조사에서는 모든 언어별 최신 릴리스 조합까지 테스트하지 않았다. [Bzlmod 패키지 통합](https://bazel.build/external/migration), [Aspect rules_js](https://github.com/aspect-build/rules_js), [Aspect rules 목록](https://docs.aspect.build/rules/), [rules_py](https://github.com/aspect-build/rules_py)

## 5. CI·원격 캐시·원격 실행

| 후보 | 역할 | 강점 | 비용·한계 |
|---|---|---|---|
| 기존 CI + setup-bazel | GitHub Actions에서 Bazelisk·캐시 설정 | CI 플랫폼을 바꾸지 않고 시작 | Bazel 전용 원격 실행 서비스는 아님 |
| bazel-remote | HTTP/gRPC 공유 캐시 | 디스크 한도·LRU, S3/GCS proxy; 작은 구성으로 출발 | executor/scheduler 없음; 인증·스토리지 운영 필요 |
| BuildBuddy | build/test UI·캐시·RBE·Workflows | 통합된 관측과 관리형/자체 호스팅 선택 | open-core; 기능별 제공 범위·견적 확인 필요 |
| EngFlow | 캐시·원격 실행·build/test UI | 관리형/자체 운영 및 엔터프라이즈 지원 | 계약·실행 인프라·운영조건 평가 필요 |
| Buildbarn | OSS 저장소·scheduler·worker·runner | 자체 통제·구성 가능성 | 클러스터·디스크·네트워크·관측 직접 운영 |
| Aspect Workflows | Bazel DX·CI 통합 | 기존 CI와 Bazel 개발흐름 연결 | 추가 CLI/config 계층; 현재 상세 문서 일부 로그인 제한 |
| bazel-diff | 두 revision의 영향 타깃 선택 | 단순 경로 필터보다 빌드 그래프 변화 반영 | 그래프·입력 누락은 해결 못함; 영향 분석 비용도 측정 |

근거: [setup-bazel](https://github.com/bazel-contrib/setup-bazel), [bazel-remote](https://github.com/buchgr/bazel-remote), [BuildBuddy](https://www.buildbuddy.io/docs/introduction/), [BuildBuddy RBE](https://www.buildbuddy.io/docs/remote-build-execution/), [EngFlow](https://docs.engflow.com/), [Buildbarn](https://github.com/buildbarn/bb-remote-execution), [Aspect 템플릿](https://github.com/aspect-build/aspect-workflows-template), [bazel-diff](https://github.com/Tinder/bazel-diff).

공유 캐시는 결과 재사용, 원격 실행은 작업을 다른 머신에서 수행하는 것이다. 같은 기능이 아니며 선택적 테스트도 별도 문제다. 처음부터 전부 도입할 필요는 없다. CI 지연이 분석 시간인지, 실제 실행인지, 다운로드인지 확인하고 추가하는 것이 이 보고서의 권고다. [Bazel 원격 캐시](https://bazel.build/remote/caching), [원격 실행을 위한 규칙](https://bazel.build/remote/rules)

실제 사례:
- Snowflake는 Java/C++ core-product repo를 Bazel로 옮기고 자체 Buildbarn 클러스터를 운영했다. 디스크·네트워크·로드밸런서 문제가 있었으며 이를 해결하는 플랫폼 투자가 필요했다. 글은 자사 구조가 전형적 마이크로서비스가 아니라고 명시하므로 MSA 사례로 둔갑시키지 않는다. [Snowflake Engineering, 2025-03-13](https://www.snowflake.com/en/blog/engineering/fast-reliable-builds-snowflake-bazel/)
- Selenium은 자체 개발 블로그에서 EngFlow build grid 사용을 설명한다. 한 프로젝트의 채택 근거이며 시장 점유율이나 보편적 성능 배수의 근거는 아니다. [Selenium, 2023-06-14](https://www.selenium.dev/blog/2023/building-selenium/)

## 6. 컨테이너와 배포

- rules_oci: OCI 이미지 조립용으로 검토할 수 있지만 현재 README는 자금 지원 없는 안정화·유지보수 모드라고 명시한다. 폐기되었다는 뜻은 아니다. [rules_oci](https://github.com/bazel-contrib/rules_oci)
- rules_img: metadata·lazy transfer·증분 load/push 등 전송 최적화를 제공하는 대안. 일부 고급 전략은 별도 캐시·registry·BES 인프라가 필요하며 자체 도구의 복잡성이 있다. 모든 환경에서 더 낫다고 단정하지 않는다. [rules_img](https://github.com/bazel-contrib/rules_img)

분석: “Bazel 도입 = 모든 배포 도구 교체”로 범위를 넓히지 않는다. 이미지 생성과 배포 승인·롤백·서비스별 출시 주기는 분리한다. rules_img가 인용하는 Stripe 발표도 Stripe의 rules_img 채택 증거로 사용하지 않는다.

## 7. 이 프로젝트에 제안하는 단계별 조합

이는 아직 적용한 설정이 아니라 조사에 따른 설계안이다.

1. 기반: Bazelisk·.bazelversion·Bzlmod·lockfile·.bazelrc·buildifier.
2. 훅: pre-commit 또는 Husky 하나만. 다언어 도구환경 설치가 중요하면 전자, 기존 npm 개발환경에 단순히 연결하면 후자.
3. 메시지: 기존 요청인 commitlint 유지 가능. Conventional Commits 검사와 최종 병합 정책을 일치시킨다.
4. CI: 포맷·메시지 정책·빌드·테스트를 필수 체크로 연결. 로컬과 동일 규칙·버전 사용.
5. 확대: BUILD 생성 수요가 있을 때 Gazelle, 그래프 기반 lint 필요시 rules_lint.
6. 가속: 공유 캐시부터 측정하고 필요하면 BuildBuddy/EngFlow/Buildbarn을 비교. bazel-diff는 누락 테스트 대조 검증 후 적용.
7. 이미지: rules_oci/rules_img를 실제 언어·registry·원격 실행 조합으로 비교.

권장 파일 배치는 팀 설계안이며 Bazel 강제 표준이 아니다:

```text
/
├── .bazelversion
├── .bazelrc
├── MODULE.bazel
├── MODULE.bazel.lock
├── .pre-commit-config.yaml   # 또는 .husky/ 중 하나
├── commitlint.config.cjs    # commitlint를 선택한 경우
├── tools/
│   ├── bootstrap/           # 개발도구 설치·훅 연결
│   ├── lint/                # 검사 실행 진입점
│   └── bazel/               # 공통 매크로·toolchain 정책
├── services/<service>/BUILD.bazel
├── libs/<library>/BUILD.bazel
└── .github/workflows/       # GitHub Actions를 사용하는 경우
```

운영 원칙: 매 커밋 전체 빌드·테스트를 강제하지 않고 짧은 검사만 둔다. source·toolchain·환경 입력을 선언하고, 신뢰하지 않는 PR에 공유 캐시 쓰기 권한·배포 비밀을 주지 않는 정책을 둔다. 단순 스크립트로 대형 native 빌드를 감싼 것만으로 세밀한 캐시·재현성이 생긴다고 가정하지 않는다. [원격 캐시 보안·재사용 조건](https://bazel.build/remote/caching), [원격 실행 규칙 제약](https://bazel.build/remote/rules)

## 범위와 검증 한계

공식 문서·maintainer README·실제 설정·기업 원저자 사례를 조사했다. 심층조사 절차에 따라 훅과 CI를 독립 조사하고 핵심 주장·반례를 재확인했으며, 이 과정에서 Lefthook 우선 추천을 수정했다.

공개 근거가 있는 주요 선택군을 폭넓게 조사했지만 모든 비공개 기업 설정과 모든 언어 ruleset의 전수조사는 아니다. 대표성 있는 Bazel 전용 점유율·동일 환경 벤치마크·계약 가격은 미확보다. GitHub main 문서는 변할 수 있고 일부 공식 페이지에는 오래된 예제가 남아 있어 버전 숫자를 그대로 권장하지 않았다. Aspect Workflows 상세 문서는 로그인 제한으로 현재 상품 세부 확인에 한계가 있다.

구현이나 훅 설치는 하지 않았다. 결과물은 Markdown이며 구조·링크 형식·내용을 검증했다. 별도 시각 렌더링은 수행하지 않았다.
