# 멀티언어 MSA 모노레포: 빌드 도구와 관리 체계 심층 비교

조사 기준일: 2026-09-06  
대상: bunsik의 아키텍처·개발 플랫폼·에이전트 조회 체계를 설계하는 의사결정자  
범위: Nx, Turborepo, Bazel, Buck2, Pants의 상세 비교와 대체 도구·네이티브 조합·전용 도구 없는 운영·도메인별 모노레포. Backstage와 LikeC4는 도입 확정으로 가정한다. 주력 언어, 서비스 수, CI 부하, 예산은 아직 확정되지 않았다고 가정한다.

공식 문서·릴리즈·기업 엔지니어링 글·공개 저장소를 세 조사 에이전트와 분담해 검토했다. 아래에서 제품 기능은 출처에 근거한 사실이며, 적합성·비용 이동·권장 구조는 이를 바탕으로 한 분석이다. 실제 저장소에서 성능 벤치마크나 도구 설치·마이그레이션을 수행한 보고서는 아니다.

## 1. 의사결정 결론

**멀티언어 MSA 모노레포에 반드시 필요한 것은 특정 도구가 아니라, 변경 영향·실행 환경·서비스 경계·배포 단위를 관리하는 체계다.** 전용 도구를 쓰면 이 체계의 일부를 제품에 맡기고, 쓰지 않으면 네이티브 빌드·CI·자체 코드로 맡게 된다.

주력 언어와 기존 생태계가 맞는다면 Nx는 좋은 후보지만, “대기업·MSA·다국어”라는 세 조건만으로 Nx나 Bazel이 정답이 되지는 않는다. 판단을 가르는 것은 다음이다.

1. **언어를 가로지르는 빌드 의존성이 얼마나 복잡한가.** 서비스 사이 HTTP 호출과 공유 Protobuf에서 생성된 여러 언어 SDK는 다른 종류의 의존성이다.
2. **정확한 증분 실행으로 줄일 수 있는 작업이 얼마나 큰가.** 대부분 시간이 외부 환경 대기나 하나의 긴 순차 테스트라면 세밀한 빌드 엔진의 이득이 제한된다.
3. **기존 빌드를 유지할 것인가, 새 빌드 모델로 옮길 것인가.** Nx와 Bazel은 이 지점의 비용 구조가 크게 다르다.
4. **누가 플러그인·규칙·캐시·업그레이드를 책임지는가.** 오픈소스 사용료가 없어도 플랫폼 유지비는 남는다.
5. **코드 저장소를 중앙화해야 하는가, 지식과 정책을 중앙화하면 되는가.** 두 선택은 독립적이다.

실제 사례도 한 방향이 아니다. Uber는 Go 모노레포에 Bazel을 도입했고, Kubernetes는 두 빌드 체계의 유지비와 Go 도구 발전을 이유로 Bazel을 제거했다. Spotify는 2023년 공개 글에서 수천 개 저장소를 유지하면서 중앙 변경·검증 자동화를 구축했다고 설명했다. 따라서 특정 기업 이름을 도구 선택의 대리 지표로 쓰기 어렵다. ([Uber, 2020](https://www.uber.com/us/en/blog/go-monorepo-bazel/), [Kubernetes 제거 제안, 2020](https://github.com/kubernetes/kubernetes/issues/88553), [Spotify, 2023](https://engineering.atspotify.com/2023/4/spotifys-shift-to-a-fleet-first-mindset-part-1))

## 2. 먼저 구분해야 하는 관리 계층

다음 표는 기능 범위를 비교하기 위한 분석 틀이다. 제품들은 여러 계층에 걸칠 수 있다.

| 계층 | 해결할 질문 | 대표 수단 |
|---|---|---|
| 소스 저장·체크아웃 | 코드가 어디 있고 필요한 부분만 가져올 수 있는가 | Git, sparse checkout, partial clone |
| 패키지·의존성 해석 | 어떤 외부/내부 버전을 사용할 것인가 | pnpm, uv, Cargo, Go modules, Maven, Gradle |
| 빌드·작업 그래프 | 무엇을 어떤 순서로 다시 실행할 것인가 | Nx, Turbo, Bazel, Buck2, Pants, Gradle |
| 실행 환경·파이프라인 | 같은 환경에서 어떻게 실행하고 캐시할 것인가 | 컨테이너, BuildKit, Dagger, Nix, CI |
| 배포·운영 상태 | 어떤 서비스 버전을 어디에 배포·롤백할 것인가 | CI/CD, GitOps, 배포 매니페스트 |
| 지식·소유권 | 이 서비스는 무엇이며 누가 책임지는가 | Backstage, LikeC4, ADR, API 명세 |
| 조직 거버넌스 | 누가 변경하고 어떤 경계를 지켜야 하는가 | CODEOWNERS, 의존성 규칙, 계약 검증, 표준 템플릿 |

Git 자체의 대형 저장소 성능은 빌드 캐시와 별개다. GitHub의 sparse-index 설명은 체크아웃한 부분에 맞춰 인덱스 규모를 줄이는 접근을 다룬다. Nx에서 빌드가 빨라져도 대형 체크아웃·Git 인덱스·IDE 인덱싱 문제가 자동 해결되지는 않는다. ([GitHub, 2021·2024 갱신](https://github.blog/open-source/git/make-your-monorepo-feel-small-with-gits-sparse-index/))

Backstage는 코드와 함께 저장된 메타데이터 YAML을 수집해 소유권과 소프트웨어 정보를 제공한다. 빌드 엔진을 바꿔야만 중앙 카탈로그를 만들 수 있는 구조가 아니다. ([Backstage Software Catalog](https://backstage.io/docs/features/software-catalog/))

## 3. 핵심 도구의 비교

아래의 “비용”은 제품 가격이나 실측 순위가 아닌, 도입·유지 작업이 생기는 위치를 비교한 것이다.

| 도구 | 주된 그래프·실행 단위 | 가장 유리한 조건 | 주된 대가 |
|---|---|---|---|
| Nx | 플러그인이 파악한 프로젝트 + 작업 | 기존 언어 도구를 유지하면서 조회·규칙·CI를 통합 | 플러그인 정확성, 추론 구성 이해, Cloud 및 통합 운영 |
| Turborepo | 패키지 매니페스트 + 스크립트 작업 | JS/TS workspace 중심, 단순한 실행·캐시 통합 | 비JS 의존성 매핑, 별도 릴리즈·정책 도구 |
| Bazel | 선언된 target + 실제 build action | 언어간 codegen·컴파일·테스트가 촘촘하고 재현성 중요 | BUILD/rules/toolchain/IDE 전환 및 원격 인프라 |
| Buck2 | target/action + 증분 엔진, BXL | 깊은 사내 빌드 플랫폼 개발 역량이 있고 언어 조합이 맞음 | 공개 toolchain 가용성, prelude/BXL/통합 코드 |
| Pants | 소스 의존성 추론 + target/process | Python 테스트·패키징·공유 코드 관리가 핵심 | 추론 예외·resolve·실험 backend 유지 |
| 네이티브 + CI | 각 언어 그래프 + 직접 정의한 상위 연결 | 서비스가 독립적이고 언어간 빌드 연결이 적음 | 상위 변경 영향·캐시·정책을 직접 관리 |

세밀한 action 엔진도 거대한 외부 빌드 명령 하나로만 감싸면 세밀한 이점을 충분히 얻지 못한다. 반대로 Nx의 프로젝트 단위 작업도 하위 Gradle·Go·컴파일러의 증분 캐시를 이용할 수 있다. “Nx는 항상 전체 재빌드, Bazel은 항상 파일 하나만 재빌드” 같은 설명은 부정확하다. Bazel의 Maven 전환 문서 역시 target을 점차 작게 나누는 과정을 강조한다. ([Bazel Maven migration](https://bazel.build/migrate/maven), [Nx 다국어 지원](https://nx.dev/docs/features/multi-language-support))

## 4. Nx: 기존 생태계를 유지하는 통합에 강하다

### 장점

Nx의 핵심은 임의 명령 실행만이 아니다. 언어별 매니페스트·설정에서 프로젝트, 작업, 의존성을 뽑아 공통 그래프로 연결하는 플러그인 구조다. JS/TS에서는 import 분석도 이용한다. 기존 Gradle/Maven 프로젝트를 Nx에 넣기 위해 기존 빌드를 버릴 필요는 없다. ([Nx 다국어 지원](https://nx.dev/docs/features/multi-language-support), [Nx Java](https://nx.dev/docs/technologies/java/introduction))

이 접근은 조직 표준화에 유리하다. 개발자는 익숙한 언어 도구를 유지하고, 플랫폼 팀은 공통 task 이름·프로젝트 조회·생성기·마이그레이션·의존성 규칙을 상위 계층에서 정리할 수 있다. 이는 기능에서 도출한 분석이며, 모든 저장소에서 설정량이 줄어든다는 보장은 아니다.

OSS 핵심 기능과 Nx Cloud도 구별해야 한다. 로컬 작업 실행·캐시·affected 같은 기능과, 여러 머신에 작업을 배분하는 Nx Agents 등 Cloud 기능의 도입 조건은 다르다. 원격 캐시만 사용할지, 분산 실행까지 맡길지 따로 결정할 수 있다. ([Nx CI](https://nx.dev/docs/features/ci-features), [Nx 가격·플랜](https://nx.dev/pricing))

### 단점과 숨은 유지비

**언어 지원의 수준이 균일하지 않다.** 조사 당시 v23 문서는 Java와 .NET 공식 지원을 설명하며 Python·Go·Rust는 Community 범주로 소개한다. Maven 통합은 experimental로 표기한다. “명령을 실행할 수 있음”과 “복잡한 언어 의존성을 공식 지원으로 정확하게 읽음”은 다르다. ([Nx 다국어 지원](https://nx.dev/docs/features/multi-language-support), [Nx Java](https://nx.dev/docs/technologies/java/introduction))

분석상 통합 계층이 늘면 장애 원인도 나뉜다. 예를 들어 Gradle은 올바르게 동작하는데 Nx의 입력 선언 때문에 오래된 결과를 복원할 수 있고, 반대로 상위 입력을 지나치게 넓게 잡아 불필요한 작업 실행을 유발할 수 있다. 플러그인 업그레이드가 추론하는 타깃이나 의존성을 바꿀 때도 회귀 검증이 필요하다.

캐시 정확성은 입력·출력 선언에 달려 있다. 누락 입력은 stale cache hit, 누락 출력은 복원 후 산출물 누락으로 이어질 수 있다. 현재 Nx에는 파일 접근을 검사하는 sandboxing이 있지만 **Nx 22.6+와 Nx Cloud dedicated compute add-on** 조건이 있으며 warning/strict 모드를 구별한다. 이 기능을 OSS 기본 실행의 보장이나 외부 네트워크·시간까지 제거하는 보장으로 확대하면 안 된다. ([Nx Task Sandboxing](https://nx.dev/docs/features/ci-features/sandboxing))

**2026년의 자체 캐시 안내는 과거와 달라졌다.** Nx는 2026-05-21부터 S3/GCS/Azure/shared-fs 캐시 패키지를 deprecated로 공지했다. 업데이트·보안패치는 중단되며, 공식 OpenAPI를 구현하는 자체 서버 경로는 남아 있다. 따라서 “자체 캐시 불가능”도, “옛 S3 플러그인만 설치하면 된다”도 부정확하다. ([Nx 캐시 패키지 폐기 공지](https://nx.dev/docs/reference/deprecated/self-hosted-cache-packages))

### 적합성 판단

Nx를 우선 검토할 조건은 TS/JS 비중이 높거나, 기존 JVM/.NET 빌드를 보존하면서 여러 팀에 동일한 개발 인터페이스를 제공하려는 경우다. Python/Go/Rust가 주력이면 실제 사용하는 플러그인의 의존성 추론·생성 코드·테스트 분할을 먼저 검증해야 한다.

최대 위험은 Nx 설정이 커지는 것 자체보다, **Nx 그래프가 실제 의존성을 모두 표현한다고 조직이 잘못 믿는 것**이다. 특히 런타임 서비스 호출 관계는 별도다.

## 5. Turborepo: 단순한 모델은 장점이며, 다국어에서는 매핑 비용이 된다

### 장점

Turbo는 package-manager workspace와 스크립트 기반 작업을 중심으로 도입할 수 있다. 비JS 프로젝트도 package.json wrapper에서 Cargo 등의 명령을 실행하고 산출물·의존성을 설정하는 공식 가이드가 있다. 소수 비JS 서비스만 섞인 JS 중심 저장소라면 이 방식은 투명하고 실용적일 수 있다. ([Turbo multi-language](https://turborepo.dev/docs/guides/multi-language), [기존 저장소 도입](https://turborepo.dev/docs/getting-started/add-to-existing-repository))

캐시와 환경변수 입력 모델을 제공하고, 원격 캐시는 Vercel 서비스 또는 자체 HTTP 서버로 연결할 수 있다. 자체 캐시나 Vercel의 원격 캐시를 이용하는 것과 애플리케이션을 Vercel에 배포하는 것은 별개다. 관리형 서비스의 비용·허용 범위는 도입 당시 플랜을 다시 확인해야 한다. ([Turbo 캐시](https://turborepo.dev/docs/crafting-your-repository/caching), [환경변수](https://turborepo.dev/docs/crafting-your-repository/using-environment-variables), [원격 캐시](https://turborepo.dev/docs/core-concepts/remote-caching))

에이전트 조회도 가능하다. 2026-03-30 발표한 2.9에서 turbo query가 stable이 되었고, GraphQL로 패키지·작업 그래프를 조회하고 affected 결과를 JSON으로 받을 수 있다. 구조화 조회는 Nx만의 장점이 아니다. ([Turborepo 2.9](https://turborepo.dev/blog/2-9))

### 단점과 숨은 유지비

비JS native 매니페스트에 있는 의존성과 Turbo가 보는 workspace 의존성 사이에 매핑이 필요하다. 서비스 몇 개면 수동 연결이 간단하지만, 수십 개 공유 라이브러리·생성 SDK·toolchain 조합이 생기면 중복 메타데이터가 틀어질 가능성이 커진다. 생성기로 줄일 수 있지만 그 생성기는 조직이 유지할 소프트웨어가 된다. 이는 공식 wrapper 패턴에서 도출한 비용 분석이다.

Strict environment는 선언된 환경변수를 다루는 장치이지, 모든 파일·프로세스·외부 서비스 접근을 완전히 격리하는 보장과 같지 않다. 비결정적인 작업이나 캐시 입력 누락 문제는 남는다. ([Turbo 환경변수](https://turborepo.dev/docs/crafting-your-repository/using-environment-variables))

패키지 릴리즈는 Changesets 등 별도 도구를 조합하는 접근이다. Nx Release처럼 통합된 흐름을 선호하는 조직에는 추가 조합이고, 작은 도구를 독립적으로 교체하려는 조직에는 장점이다. ([Turbo 라이브러리 게시](https://turborepo.dev/docs/guides/publishing-libraries), [Nx independent release](https://nx.dev/docs/guides/nx-release/release-projects-independently))

조사한 공식 자료에서 Turbo 자체가 Nx Agents와 같은 방식으로 여러 머신에 작업을 분배하는 기능은 확인하지 못했다. CI matrix 등으로 구성할 수 있다는 것과 도구 자체가 분산 실행을 제공한다는 것은 구별해야 한다.

### 적합성 판단

JS/TS workspace가 안정적이고 실행·캐시 통합이 주목적이면 좋은 후보다. 다언어 서비스가 존재한다는 이유만으로 배제할 필요는 없다. 다만 **다언어 공유 코드의 관계가 복잡할수록 수동 연결의 유지비**를 Nx 플러그인이나 Bazel/Pants 그래프와 비교해야 한다.

## 6. Bazel: 정밀한 빌드 모델의 이익과 전환 비용이 함께 크다

### 장점

Bazel은 라이브러리·바이너리·테스트 등의 target과 실제 action을 통해 빌드를 모델링한다. 언어별 컴파일만이 아니라 공통 schema에서 여러 언어 코드를 생성하고 각각 테스트·패키징하는 연결을 명시적으로 관리할 때 가치가 크다. 긴 순차 작업 몇 개만 있는 빌드는 이점이 제한될 수 있다고 공식 FAQ도 설명한다. ([Bazel FAQ](https://bazel.build/about/faq))

원격 캐시는 이미 실행한 결과를 공유하고, 원격 실행은 아직 실행해야 할 action을 원격 작업자에게 맡긴다. 전자는 후자 없이도 가능하다. 표준 프로토콜을 이용하므로 실행 인프라 선택 여지가 있지만 서버·네트워크·권한·용량 운영은 별도다. ([Bazel remote caching](https://bazel.build/remote/caching), [Remote execution](https://bazel.build/remote/rbe))

조회 능력도 강점이다. query는 의존성과 역의존성, 두 target 사이 경로를 찾는 데 사용할 수 있다. cquery는 구성 적용 결과, aquery는 action 수준 분석을 위한 별도 관점이다. 빌드 영향과 생성물의 근거를 에이전트에 제공할 때 유용하다. ([Bazel query guide](https://bazel.build/query/guide))

### 단점과 숨은 유지비

기존 빌드와의 의미 차이를 해결해야 한다. Maven artifact를 사용한다고 Maven plugin이 그대로 실행되는 것은 아니다. 공식 전환 문서는 기존 빌드를 병행하다가 점차 새 모델로 옮기고 target을 세분화하는 과정을 설명한다. 즉 최초 BUILD 작성뿐 아니라 **규칙·의존성 해석·CI·개발자 경험의 전환**이 비용이다. ([Maven에서 Bazel로 전환](https://bazel.build/migrate/maven))

예를 들어 모든 서비스에 “Gradle 전체 빌드를 실행하는 action” 하나만 만들면 상위 캐시는 얻을 수 있어도 내부 컴파일 action을 정밀하게 분배하기 어렵다. 그러면 Nx 위에서 Gradle을 실행하는 것보다 전환 부담만 커질 수도 있다. 실제 이익은 얼마나 깊이 빌드 모델을 옮겼는지에 달린다는 분석이다.

Hermeticity도 자동 마법이 아니다. 로컬 PATH/JAVA_HOME에 기대는 도구 탐색, action 사이 암묵적인 compiler 상태, 실행 플랫폼과 맞지 않는 바이너리는 원격 실행에서 문제가 된다. toolchain과 입력을 명시하고 실행 플랫폼을 관리해야 한다. ([원격 실행에 맞춘 규칙](https://bazel.build/remote/rules))

타임스탬프·난수·네트워크 데이터를 생성물에 섞는 custom 작업은 별도 주의가 필요하다. 재현성을 위한 기능이 있다는 사실과 어느 프로젝트의 모든 산출물이 재현 가능하다는 결론은 다르다. ([Bazel FAQ의 reproducibility 조건](https://bazel.build/about/faq))

OCI 패키징도 규칙 생태계를 검토해야 한다. 조사 당시 rules_oci는 “stable in maintenance mode” 상태를 명시하고, 특정 원격 실행·전송 효율 요구에는 rules_img 검토를 권고한다. maintenance mode를 폐기라고 해석할 수는 없지만, 코어가 활발하다고 필요한 모든 확장이 같은 지원 상태인 것은 아니다. ([rules_oci README](https://github.com/bazel-contrib/rules_oci))

### 적합성 판단

복잡한 생성 코드·다중 플랫폼·많은 컴파일 및 테스트가 서로 연결되고, 그 작업량을 정밀하게 줄일 여지가 클 때 검토한다. 서비스가 독립된 Dockerfile 몇 개로 충분하고 빌드도 짧다면 추가 모델 유지비를 상쇄하기 어렵다.

Google 내부 Blaze와 공개 Bazel도 구별해야 한다. 공통 코드가 많아도 Google 특화 인프라 전체를 공개 Bazel 설치만으로 얻는 것은 아니다. ([Bazel의 기원·비공개 확장 설명](https://bazel.build/about/faq))

## 7. Buck2: 맞춤형 대규모 빌드 플랫폼에 강하지만 외부 도입 조건을 먼저 확인해야 한다

### 장점

Buck2는 Rust 코어와 Starlark 규칙을 분리하고 증분 그래프·원격 실행을 기반으로 한다. Meta는 2023년 공개 발표에서 사내 대규모 사용과 Buck1 대비 개선을 설명했다. 이는 엔진의 실전 사용 근거지만 다른 도구보다 빠르다는 비교 결과는 아니다. ([Meta Buck2 공개 발표, 2023-04-06](https://engineering.fb.com/2023/04/06/open-source/buck2-open-source-large-scale-build-system/))

BXL은 그래프를 조회하고 분석·빌드 작업을 수행하는 확장 계층이다. CLI 문자열을 여러 번 조합하는 대신 그래프 객체를 다루고, IDE 프로젝트 정보 생성 같은 조직별 작업을 구성할 수 있다. 빌드 그래프를 사내 개발 플랫폼의 데이터로 적극 활용하려는 팀에 매력적이다. ([Buck2 Why BXL](https://buck2.build/docs/bxl/))

### 단점과 숨은 유지비

**Prelude에 규칙이 존재하는 것과 외부에서 바로 사용 가능한 것은 다르다.** 공식 지원표는 C++·Java·Kotlin을 Complex Setup, Go·Python·Rust 등을 Easy Setup으로 표시하고, C#·Objective-C·Swift는 필요한 도구가 없어 Unavailable로 표시한다. 표 자체와 개별 문서의 갱신 수준에 차이가 있으므로 실제 필요한 toolchain 조합으로 확인해야 한다. ([Buck2 언어 지원표](https://buck2.build/docs/about/language_support/))

Meta의 공개 발표도 내부와 외부의 toolchain·원격 서버 차이를 설명한다. 따라서 Meta의 사용 규모를 근거로 소규모 팀의 도입 난도가 낮다고 추론할 수 없다. ([Meta 공개 발표](https://engineering.fb.com/2023/04/06/open-source/buck2-open-source-large-scale-build-system/))

Buck2 README는 원격 실행 사용 시 미선언 입력에 접근할 수 없는 조건에서 hermeticity를 설명한다. 임의 로컬 실행까지 똑같은 격리 보장이 있다고 단정하지 않는다. ([Buck2 README](https://github.com/facebook/buck2))

분석상 유지비는 BUCK 파일뿐 아니라 prelude/toolchain 버전, 조직별 규칙, BXL 조회 계층, IDE 연동에 생긴다. 강한 확장성은 플랫폼 개발 역량이 있을 때 장점이고, 그 역량이 없으면 도입 장벽이다.

### 적합성 판단

기존 Buck 경험이 있거나 자체 빌드 인프라를 적극 개발할 조직이라면 중요한 후보다. bunsik처럼 언어와 서비스 구성도 아직 미정인 상태에서 “Meta가 쓰니까” 우선 도입할 이유는 약하다. 먼저 필요한 언어·프레임워크·IDE가 공개 배포 환경에서 동작하는지 확인해야 한다.

## 8. Pants: Python 중심의 세밀한 그래프를 적은 수작업으로 유지하는 데 강하다

### 장점

Pants의 중요한 차별점은 의존성 추론이다. 정적 import 등을 분석하여 상세한 의존성을 파악하고 파일 단위 무효화·캐시·병렬화에 활용한다. BUILD 메타데이터가 사라지는 것은 아니지만 의존성 목록을 사람이 모두 작성하는 부담을 줄인다. Bazel에도 BUILD 생성 수단이 있으므로 “자동 생성 대 수작업”이라는 이분법은 피해야 한다. ([Pants dependency inference, 2022-10-27](https://www.pantsbuild.org/blog/2022/10/27/why-dependency-inference))

기본 로컬 실행·캐시 외에 REAPI를 통한 원격 캐시·원격 실행을 지원한다. Bazel과 같은 프로토콜 계열을 쓸 수 있다는 것은 서버 연결의 장점이며, 서로 다른 빌드 도구가 자동으로 같은 캐시 키를 만들어 결과를 공유한다는 뜻은 아니다. ([Pants remote caching & execution](https://www.pantsbuild.org/stable/docs/using-pants/remote-caching-and-execution))

Python 서비스마다 상충하는 의존성이 있으면 여러 resolve/lockfile을 둘 수 있다. 다만 한 target의 전이 의존성은 같은 resolve에 속해야 하고, 공유 코드를 여러 resolve에 걸쳐 사용할 때는 별도 모델링이 필요하다. ([Pants lockfiles](https://www.pantsbuild.org/stable/docs/python/overview/lockfiles))

PEX를 이용한 Python 패키징도 통합되어 있다. 실행 환경에 적합한 Python interpreter와 플랫폼별 의존성 조건은 여전히 확인해야 한다. 특히 다른 플랫폼용 native dependency의 wheel 가용성은 별도 제약이다. ([Pants PEX](https://www.pantsbuild.org/stable/docs/python/overview/pex))

### 단점과 숨은 유지비

조사 당시 stable 2.33 문서의 backend 표에서 Python·Shell·Docker는 stable이지만 Go·JVM·JavaScript·Rust 등은 experimental 범주다. 실험 기능은 변경 경고가 적거나 없이 큰 변화가 있을 수 있다고 문서가 설명한다. 생산 사용 불가라는 뜻은 아니지만, 다언어 전체 표준화에서는 검토해야 할 비용이다. ([Pants backends](https://www.pantsbuild.org/stable/docs/using-pants/key-concepts/backends))

자동 추론은 동적 import·프레임워크 plugin·문자열 설정·resource 참조에서 보정이 필요할 수 있다. Python 추론 문서는 문자열 기반 추론, 소유자가 불명확한 import, 예외 처리 옵션을 구별한다. 수작업 의존성 관리가 줄어든 대신 추론의 사각지대를 진단하는 역량이 필요하다는 분석이다. ([Pants python-infer](https://www.pantsbuild.org/stable/reference/subsystems/python-infer))

대부분 작업을 sandbox에서 실행하므로 암묵적 cwd·로컬 파일·환경에 기대던 테스트가 전환 중 깨질 수 있다. 이는 숨은 의존성을 드러내는 장점이지만 마이그레이션 작업량에도 포함해야 한다. 샌드박스 보존과 재현 도구가 제공된다. ([Pants troubleshooting](https://www.pantsbuild.org/stable/docs/using-pants/troubleshooting-common-issues))

### 적합성 판단

Python 서비스·데이터·ML 코드가 핵심이고 공유 코드의 테스트·패키징·의존성 충돌이 문제라면 강력한 후보다. Python이 소수이고 Java·TS가 대부분인 저장소에 전체 표준으로 먼저 적용하는 것은 지원 수준에 비해 부담이 클 수 있다.

Oxbotica의 2022년 사례는 Python 모노레포를 점진적으로 Pants로 옮긴 경험이다. 이를 전사 모든 언어에 대한 검증으로 확대하지 않아야 한다. ([Oxbotica 도입 회고, 2022-11-04](https://www.pantsbuild.org/blog/2022/11/04/introducing-pants-to-oxbotica))

## 9. 이 다섯 개가 전부가 아니다

다음은 직접 경쟁하거나 다른 계층에서 대체·보완할 수 있는 도구다. 이 보고서는 핵심 다섯 도구를 깊게 비교하고, 나머지는 도입 후보를 빠뜨리지 않도록 기능 범위와 주요 비용을 검토했다. 모든 하위 플러그인까지 동일 깊이로 실측 평가한 것은 아니다.

| 선택지 | 장점과 역할 | 한계·확인할 비용 |
|---|---|---|
| **moon / proto** | 작업 그래프와 도구 버전 설치를 함께 관리. 언어 지원을 tier로 구분 | 명령 실행·생태계 분석·toolchain 설치 지원을 각각 확인해야 함 |
| **Rush** | 대형 JS 조직의 설치·버전 정책·패키지 게시·캐시 관리 | 일반적인 Python/JVM/Go 통합 그래프의 대체재로 가정하면 안 됨 |
| **Lage + BuildXL** | JS 작업 그래프와 sandbox/cache/분산 실행 엔진을 분리하여 조합 | 두 도구의 연동·플랫폼 지원·업그레이드를 함께 관리 |
| **Please** | 별도의 cross-language 빌드 엔진. hermetic 실행·증분·규칙 확장 지향 | 필요한 언어 규칙·IDE·조직 지원 역량을 검증해야 함 |
| **Gradle / Maven** | JVM 안에서는 이미 다중 프로젝트와 실행 순서를 관리 | 언어 밖 의존성을 연결할 상위 계층은 별도 |
| **Dagger** | 코드로 컨테이너 파이프라인을 작성해 로컬·CI에서 재사용 | import 기반 전역 소스 그래프가 자동으로 생기는 것은 아님 |
| **BuildKit / Buildx Bake** | 컨테이너 이미지 빌드·캐시·병렬 구성을 중심으로 통합 | 이미지 그래프와 전체 코드·테스트 영향 그래프는 다름 |
| **Nix** | 도구·시스템 의존성 및 환경 재현성을 관리 | 언어 생태계 연결과 Nix 표현식 유지비. 모든 산출물의 결정성 자동 보장 아님 |
| **mise / Make / Task / just** | 공통 명령·도구 환경·간단한 작업 연결에 활용 | 제품별 지원 범위가 다름. 파일 소유권·의미적 역의존성은 별도 검증 |
| **Earthly** | 컨테이너 중심 빌드 접근의 역사적 후보 | 원 프로젝트의 적극적 유지보수 종료 공지 때문에 신규 도입은 유지 주체 확인부터 |

moon의 현재 문서는 v2이며, 단순 언어 인식·생태계 통합·도구 설치를 구분한다. 지원 언어가 목록에 있다는 사실만으로 모든 tier가 충족된다고 보면 안 된다. ([moon 언어 지원](https://moonrepo.dev/docs/how-it-works/languages))

Rush의 build cache와 게시 정책은 JS 패키지 조직 관리의 기능이다. Lage 문서는 자체 single-node 실행과 BuildXL에 위임하는 분산 실행을 구별한다. ([Rush cache](https://rushjs.io/pages/maintainer/build_cache/), [Rush publishing](https://rushjs.io/pages/maintainer/publishing/), [Lage distributed builds](https://microsoft.github.io/lage/docs/guides/buildxl/))

Please 역시 고성능·정확성을 지향하는 다언어 빌드 시스템으로 별도 후보가 된다. 다만 홈페이지의 장점 설명만으로 Bazel/Buck2보다 낮은 운영비나 높은 성능을 확정할 수는 없다. ([Please](https://please.build/))

Dagger는 모노레포 전체 모듈이 하위 모듈을 조율하는 방식과, 여러 서비스가 공통 자동화 모듈을 공유하는 방식을 문서화한다. **빌드 환경·CI 재사용이 병목이고 서비스 사이 소스 공유가 적다면**, 정밀한 소스 그래프보다 이 접근이 먼저 효과를 낼 수 있다는 분석이다. ([Dagger monorepos](https://docs.dagger.io/0.21/reference/best-practices/monorepos/))

Bake는 선언적인 이미지 빌드 구성을 제공한다. Nix는 sandbox와 명시적 의존성을 통해 재현 가능한 빌드의 기반을 제공하지만, NixOS 자체 설명도 타임스탬프 등 비결정성 제거가 추가로 필요하다고 밝힌다. ([Docker Bake](https://docs.docker.com/build/bake/), [NixOS reproducible builds](https://reproducible.nixos.org/))

mise도 현재 문서에서 하위 프로젝트별 task 발견·경로 namespace·도구 환경 상속을 지원한다. 단순한 버전 매니저로만 분류하기보다 실제 사용하는 버전의 task·cache 기능 범위를 확인하는 편이 정확하다. ([mise monorepo tasks](https://mise.jdx.dev/tasks/monorepo.html))

Earthly는 2025-04-16 공지에서 적극적인 OSS 유지보수 종료와 Cloud/Satellites의 2025-07-16 종료 계획을 밝혔다. 따라서 오래된 추천 목록을 그대로 사용하면 안 된다. 커뮤니티 fork는 그 fork의 유지 상태를 별도로 평가해야 한다. ([Earthly 공식 공지](https://earthly.dev/blog/shutting-down-earthfiles-cloud/))

## 10. 전용 모노레포 도구 없이 운영하는 방법

**가능하다. 다만 “Nx/Bazel/Pants 없음”은 “빌드 관리도 없음”을 뜻하지 않는다.** 네이티브 도구·컨테이너·CI와 필요한 연결 코드가 그 역할을 맡는다.

### 방식 A: 네이티브 workspace + 얇은 공통 명령

JS/TS는 package-manager workspace, Go는 go.work/modules, Rust는 Cargo workspace, Python은 uv 프로젝트/workspace, JVM은 Gradle multi-project/composite build 또는 Maven reactor를 이용한다. 루트의 공통 명령이 해당 언어 작업을 호출한다.

이들 도구는 이미 자기 언어의 의존성과 작업 실행에 필요한 상당한 정보를 갖고 있다. 특히 Maven reactor는 모듈을 수집하고 빌드 순서를 정하며, Cargo workspace는 여러 패키지의 공통 실행·설정 관리를 지원한다. ([Go workspace](https://go.dev/doc/tutorial/workspaces), [Cargo workspace](https://doc.rust-lang.org/cargo/reference/workspaces.html), [Gradle multi-project](https://docs.gradle.org/current/userguide/multi_project_builds.html), [Gradle composite](https://docs.gradle.org/current/userguide/composite_builds.html), [Maven reactor](https://maven.apache.org/guides/mini/guide-multiple-modules.html))

장점은 기존 IDE·디버거·패키지 게시 흐름과 가깝고 초기 도입 비용이 낮다는 점이다. 단점은 Go 그래프가 Python 소비자까지, Cargo 그래프가 TS SDK까지 자동으로 알지는 못한다는 점이다. 언어간 연결을 공통 manifest나 CI에서 관리해야 한다는 분석이다.

**모노레포는 단일 lockfile을 강제하지 않는다.** uv는 상충하는 의존성이나 별도 가상환경이 필요한 프로젝트에 독립 프로젝트+path dependency가 더 적합할 수 있다고 설명한다. 공유 workspace가 다른 멤버의 의존성을 몰래 import하는 것까지 차단하는 것도 아니다. 서비스별 독립 진화가 중요하면 언어 단위·도메인 단위·서비스 단위 lock 범위를 의도적으로 정해야 한다. ([uv workspaces](https://docs.astral.sh/uv/concepts/projects/workspaces/))

### 방식 B: 서비스별 파이프라인 + 경로 필터

변경된 폴더에 대응하는 테스트·컨테이너 빌드를 실행한다. GitLab의 공식 Java/Python 모노레포 예제는 디렉터리별 파이프라인을 경로 조건으로 선택하는 패턴을 제시한다. 이는 실제 가능한 구성 패턴이며, 그 자체가 대규모 기업 성능의 검증은 아니다. ([GitLab 모노레포 CI 예제, 2024-07-30](https://about.gitlab.com/blog/building-a-gitlab-ci-cd-pipeline-for-a-monorepo-the-easy-way/))

서비스 사이 공유 소스가 적으면 간단하고 명시적이다. 그러나 다음 변화도 처리해야 한다.

- 공통 Protobuf/OpenAPI/이벤트 schema 변경
- 공통 Docker base image 또는 compiler 버전 변경
- 루트 lockfile·공통 CI template·테스트 fixture 변경
- 라이브러리 파일의 이동·삭제와 역의존성 변화

경로 필터는 관계의 의미를 스스로 알아내지 않는다. 공유 입력 변화에는 소비자 목록을 연결하거나 보수적으로 넓게 실행해야 한다. CI 조건은 branch·tag·schedule 등 이벤트에 따라 동작이 달라질 수 있어 기준 commit과 fallback도 필요하다. ([GitLab job rules](https://docs.gitlab.com/ci/jobs/job_rules/), [CI debugging](https://docs.gitlab.com/ci/debugging/))

### 방식 C: 컨테이너 파이프라인 중심

각 서비스가 Dockerfile로 toolchain과 패키징을 정의하고, Make/Compose/Bake/Skaffold/Dagger 중 필요한 계층을 조합한다. 서비스별 환경 차이를 허용하면서 공통 실행 경험을 제공하기 쉽다.

장점은 언어 도구를 새 빌드 DSL로 옮기는 범위가 작다는 점이다. 단점은 Docker context를 지나치게 넓게 잡으면 무관한 변경으로 캐시가 깨지고, codegen·테스트 입력이 컨테이너 구성 밖에 있으면 별도 연결이 필요하다는 점이다. “컨테이너로 실행됨”과 “선언된 모든 입력이 정확히 관리됨”도 다르다.

### 방식 D: 자체 변경 영향 분석 시스템

Git diff, 언어별 dependency 정보, 테스트 coverage/fixture 관계, 서비스 manifest를 조합해 실행할 작업을 계산한다. 처음에는 짧은 스크립트여도 규모가 커지면 변경 유형·예외·fallback·설명 기능을 갖춘 내부 제품이 된다.

장점은 회사 특유의 관계를 정확하게 표현할 수 있다는 점이다. 단점은 범용 도구의 라이선스 대신 추론·캐시·스케줄링·운영 지식의 유지비를 직접 부담한다는 점이다. GitLab의 자체 predictive test 체계가 좋은 예다. ([GitLab 자체 파이프라인](https://docs.gitlab.com/development/pipelines/))

### 방식 E: 도메인별 모노레포 또는 polyrepo + 중앙 플랫폼

결합이 강한 서비스·SDK는 같은 저장소에 묶고, 결합이 낮거나 권한·릴리즈 요구가 다른 도메인은 분리한다. Backstage·LikeC4·공통 CI template·중앙 검색은 전역으로 유지한다.

한 PR에서 전체 변경을 원자적으로 합치는 편의는 줄어든다. 대신 각 도메인이 언어·빌드·릴리즈를 독립적으로 발전시키기 쉽다. 경계 밖 변경에는 버전·API 호환성·변경 전파 자동화가 필요하다. **중앙 지식 관리가 목표라는 이유만으로 전사 단일 저장소를 강제할 필요는 없다.**

Spotify는 2023년 수천 개 GitHub 저장소를 가진 polyrepo에서 코드·구성·운영 정보를 조회하고 대규모 변경을 자동 적용·검증하는 fleet management를 설명했다. 이것은 모노레포 사례가 아니라, 중앙 관리와 저장소 단일화가 독립이라는 실전 근거다. ([Spotify Fleet Management, 2023-04-18](https://engineering.atspotify.com/2023/4/spotifys-shift-to-a-fleet-first-mindset-part-1))

## 11. 실제 사례: 무엇을 입증하며 어디까지 일반화할 수 있는가

| 사례 | 공개된 운영 방식 | 입증하는 것 | 일반화하면 안 되는 것 |
|---|---|---|---|
| Uber, 2020 | Go 모노레포에 Bazel·Gazelle·원격 캐시·기존 제출 체계 연동 | 커진 공유 Go 코드와 빌드 요구에 정밀 엔진을 도입한 사례 | Uber 전사 모든 언어가 한 저장소·한 도구라는 주장 |
| Meta, 2023 | Buck2를 사내 대규모 빌드에 사용 | 엔진의 대규모 실전 사용 | Buck1 대비 개선을 Nx/Bazel 대비 개선으로 해석 |
| Caseware, 2026 | Java/C#/frontend 포함 700+ 프로젝트를 Nx로 관리 | Nx의 실제 대규모 다언어 사용 | 700개 프로젝트를 독립 MSA 700개로 해석 |
| Vercel, 2026 | Turbo 2.9 글에서 자사 backend/frontend 저장소 측정 | Turbo가 작은 프런트엔드 예제에만 쓰이는 것은 아님 | 최초 작업 시작 시간 개선을 전체 CI 개선으로 해석 |
| Oxbotica, 2022 | Python 모노레포를 Pants로 단계적 전환 | Python 도메인에서 추론·테스트·환경 관리의 활용 | 모든 언어에 대한 전사 표준 사례 |
| Kubernetes, 2020–2021 | Bazel 제거 제안과 실제 제거 PR | 도구의 추가 가치보다 이중 유지비가 커질 수 있음 | Go 중심 사례로 모든 다언어 MSA의 결론 도출 |
| GitLab, 현재 개발 문서 | RSpec/Jest·자체 detect-tests·CI 계층, Workhorse의 Go/Make | 네이티브 도구+자체 영향 분석으로 복합 제품을 관리 | 회사 모든 저장소에서 전용 도구를 전혀 안 쓴다고 단정 |
| Google Online Boutique | 다언어 gRPC 서비스·Skaffold·Docker 빌드 | 전용 소스 그래프 엔진 없이 MSA를 구성하는 공개 예제 | Google의 대규모 운영 MSA 인프라라고 주장 |
| OpenTelemetry Demo | Make·Compose·Buildx 기반 다언어 분산 시스템 예제 | 다양한 언어를 컨테이너 경계로 묶는 실행 가능한 예제 | 실제 대기업 생산 서비스의 규모·SLO 검증 |
| Spotify, 2023 | Polyrepo + fleet-wide 검색·변경·검증 자동화 | 중앙 정책·조회가 단일 저장소를 요구하지 않음 | 모노레포 사례로 분류하거나 2026 상태로 단정 |

Uber의 당시 Go 코드 규모·도입 과정을 담은 원문과 Meta의 Buck2 공개 글은 각각 원저자 기술 사례다. 과거의 IDE 제약을 현재 버전의 제약으로 그대로 옮기지 않았다. ([Uber](https://www.uber.com/us/en/blog/go-monorepo-bazel/), [Meta](https://engineering.fb.com/2023/04/06/open-source/buck2-open-source-large-scale-build-system/))

Caseware는 Nx가 게시한 고객 성공 사례다. “700+ projects”는 활용 범위의 근거로 쓰되, 벤더의 compute savings를 우리 조직의 예상 비용 절감으로 환산하지 않았다. 같은 사례의 블로그와 고객 페이지 표기 날짜도 다르므로 여기서는 2026년 사례로만 묶었다. ([Caseware 고객 사례](https://nx.dev/customer-stories/scaling-700-projects-how-nx-became-a-no-brainer-for-caseware))

Vercel의 2.9 발표는 자사 backend 저장소 1,037개 패키지에서 최초 작업 시작 시간을 비교한다. 이것은 패키지 개수와 특정 성능 지표의 사례이지, 언어 구성 전체나 서비스 개수·전체 CI 지연을 뜻하지 않는다. ([Turbo 2.9 측정 범위](https://turborepo.dev/blog/2-9))

Kubernetes는 두 빌드 체계 동기화 비용과 Go modules/cache의 발전을 제거 이유로 제시했고 2021년 제거 PR을 병합했다. 제거 논의에는 의존성 경계 검증을 Go internal·자체 검사로 대체하는 문제도 포함되어 있다. 도구를 없애도 필요한 규칙의 책임이 없어지지는 않는다. ([제거 이유](https://github.com/kubernetes/kubernetes/issues/88553), [실제 제거 PR](https://github.com/kubernetes/kubernetes/pull/99561))

GitLab은 backend에서 만든 fixture 때문에 frontend Jest도 backend 변경의 영향을 받는다고 명시한다. 단순 폴더별 필터의 사각지대를 자체 매핑·예측·전체 테스트로 보완하는 사례다. Workhorse 개발 문서는 Go와 GNU Make를 요구한다. ([GitLab pipelines](https://docs.gitlab.com/development/pipelines/), [Workhorse](https://docs.gitlab.com/development/workhorse/))

Online Boutique의 개발 가이드는 Skaffold가 이미지 빌드·게시·Kubernetes 배포를 수행하도록 안내한다. OpenTelemetry Demo의 Makefile은 서비스별 Compose build와 Buildx 다중 플랫폼 빌드를 실제로 정의한다. 두 사례는 공개 실행 구조의 근거이며, 기업의 전사 운영 규모를 입증하는 자료는 아니다. ([Online Boutique](https://github.com/GoogleCloudPlatform/microservices-demo), [개발 가이드](https://github.com/GoogleCloudPlatform/microservices-demo/blob/main/docs/development-guide.md), [OTel Demo](https://github.com/open-telemetry/opentelemetry-demo), [OTel Makefile](https://github.com/open-telemetry/opentelemetry-demo/blob/main/Makefile))

## 12. MSA에서 빌드 도구 비교보다 먼저 해결할 관계

다음은 설계 권고다. **하나의 dependency 관계로 모든 영향을 표현하지 않는 것**이 핵심이다.

| 관계 | 예 | 재빌드·검증·배포에 미치는 의미 |
|---|---|---|
| build dependency | 결제 SDK가 payment.proto에서 생성됨 | schema 변경 시 SDK와 해당 소비자 빌드·테스트 검토 |
| runtime dependency | 주문 서비스가 결제 API를 호출 | 계약·장애 전파 검토. 결제 내부 수정만으로 주문 재빌드가 항상 필요한 것은 아님 |
| deployment dependency | 새 코드가 새 DB 필드를 요구 | schema 변경과 코드 rollout 순서 검토 |
| ownership / policy | 결제 팀이 결제 서비스를 소유 | 리뷰·문의·운영 책임. 빌드 순서와는 별개 |

예를 들어 payment.proto에서 필드를 삭제하면 Go 서버·Python 소비자·TS 클라이언트가 모두 같은 PR에서 컴파일될 수 있다. 그래도 운영 환경에 남아 있는 구버전 클라이언트가 호환되는지는 별도다. **한 커밋의 일관성은 서비스 버전 조합의 운영 호환성을 보장하지 않는다.**

Protobuf의 breaking-change 검사는 schema 차이를 검사하고, Pact의 can-i-deploy는 소비자·제공자 버전 사이 검증 결과를 이용한다. 어떤 도구를 쓰든 이런 계약·버전 검증은 빌드 그래프와 별도로 설계해야 한다. ([Buf breaking detection](https://buf.build/docs/breaking/), [Pact can-i-deploy](https://docs.pact.io/pact_broker/can_i_deploy))

권고하는 운영 단위는 서비스별 artifact와 배포 기록이다. 동일 Git SHA에서 여러 서비스 이미지를 만들 수 있지만, 배포·롤백은 서비스별 digest와 환경 상태를 기준으로 한다. 공통 라이브러리 변경 시 “다시 검증할 소비자”와 “당장 배포할 서비스”를 같은 목록으로 자동 취급하지 않는다.

공유 코드도 종류를 나누는 편이 좋다. 통신 계약·관측성·인증 기반 코드는 공통화할 수 있지만, 서비스 내부 도메인 모델을 서로 직접 import하면 독립 배포가 어려워질 수 있다. 이는 모노레포 엔진의 문제가 아니라 경계 설계의 문제다.

## 13. 캐시·병렬화·재현성을 평가할 때 생기는 오판

### 캐시 적중률이 높다고 반드시 좋은 것은 아니다

이하는 설계 분석이다. 입력이 빠진 캐시는 결과가 바뀌어야 할 상황에서도 적중한다. 따라서 캐시 적중률을 높이는 것보다 먼저 **반드시 무효화되어야 할 변경에서 실제로 무효화되는지** 확인해야 한다.

반대로 모든 작업의 입력에 저장소 전체를 넣으면 안전한 편이지만 작은 변경도 거의 전부 무효화한다. 이때 캐시 문제로 보이는 현상의 실제 원인은 그래프·입력 모델이 너무 거친 것이다. Nx의 sandbox 문서는 미선언 입력·출력으로 생기는 문제를 구체적으로 설명한다. ([Nx cache correctness](https://nx.dev/docs/features/ci-features/sandboxing))

### 서로 다른 캐시 계층을 구분한다

| 계층 | 저장하는 것 | 오해하면 안 되는 점 |
|---|---|---|
| 패키지 다운로드 캐시 | wheel, jar, npm tarball 등 | 테스트·컴파일 결과 캐시와 다름 |
| 컴파일러/언어 빌드 캐시 | 모듈·컴파일 작업 결과 | 다른 언어 소비자의 작업 선택까지 맡지 않음 |
| task/action cache | 선언된 입력에 대한 실행 결과 | 입력 모델 밖 변경은 놓칠 수 있음 |
| 컨테이너 layer cache | 이미지 빌드 단계 결과 | 서비스 계약 호환성의 검증 결과가 아님 |
| 원격 실행 | 미실행 작업의 원격 처리 | 캐시와 별도. 네트워크·큐·worker 준비 비용 존재 |

이 구분은 Bazel과 Pants가 각각 설명하는 remote cache/execution 의미와도 일치한다. 표준 REAPI 서버를 함께 쓸 수 있어도 서로 다른 빌드 도구의 action 정의가 같지 않으면 결과 캐시 적중을 공유하지 못한다. ([Bazel remote caching](https://bazel.build/remote/caching), [Pants REAPI](https://www.pantsbuild.org/stable/docs/using-pants/remote-caching-and-execution))

### 중첩 도구는 역할을 정하면 유용하다

Nx → Gradle, 상위 CI → Pants, Dagger → native build처럼 계층을 나누는 것은 합리적일 수 있다. 하지만 상위·하위 도구가 같은 artifact의 입력·출력·캐시 복원을 각각 다르게 판단하면 진단이 어려워진다.

권고는 **같은 산출물에 대한 책임을 분명히 하는 것**이다. 상위 도구는 프로젝트 선택·공통 명령·관측을 맡고, 하위 도구는 세부 빌드·패키징을 맡게 한다. 상위 결과 캐시가 필요한 경우에는 하위 입력과 출력이 정확히 반영되는지 검증한다. 단순히 캐시를 두 번 켜는 것을 최적화로 보지 않는다.

### 원격 캐시는 신뢰 경계다

실행 결과가 캐시에서 그대로 복원되므로 누가 쓸 수 있는지와 어떤 branch·CI 신뢰 수준의 산출물인지가 중요하다. Nx의 2026년 캐시 패키지 폐기 공지는 이러한 설계 위험을 실제로 다룬다. 이는 특정 제품 비교에 필요한 운영 비용 항목이지, 모든 캐시 서비스를 동일하게 취약하다고 단정할 근거는 아니다. ([Nx 캐시 설계 변경 공지](https://nx.dev/docs/reference/deprecated/self-hosted-cache-packages))

도입 검증에서는 신뢰되지 않은 PR의 cache write 권한, artifact 변경 방지, 읽기·쓰기 주체 분리, 오염 발생 시 복구 경로를 제품/인프라별로 확인한다.

### 빌드 성공을 배포 성공으로 캐시하지 않는다

빌드 산출물은 같은 입력이면 재사용할 수 있지만 외부 DB·운영 환경을 변경하는 작업은 외부 상태를 가진다. 배포·마이그레이션·게시를 일반 build cache의 성공 결과로 대체하면 실행이 생략되는 문제가 생길 수 있다. 배포를 명령으로 호출할 수 있는가와 그 결과를 캐시해도 되는가는 다른 질문이다. ([Bazel FAQ의 외부 상태 작업 설명](https://bazel.build/about/faq))

## 14. 개발 에이전트와 중앙 지식 조회: 도구에 종속되지 않는 설계

Backstage·LikeC4가 확정되어 있다면, **빌드 도구는 지식 원본의 일부를 제공하는 adapter로 취급하는 것**을 권고한다. 전체 지식 저장 모델을 Nx project.json에 넣거나 모든 그래프를 LikeC4에 손으로 복제하지 않는다.

### 원본과 조회 역할

| 정보 | 권고 원본 | 에이전트 조회 |
|---|---|---|
| 프로젝트·타깃·빌드 의존성 | 선택한 빌드 도구의 해석 결과 | 해당 도구의 구조화 CLI/API |
| 소유 팀·시스템·수명주기 | Backstage catalog YAML 또는 명시한 권위 원천 | Catalog API / Git 원본 |
| 시스템 경계·호출·데이터 흐름 | LikeC4 모델 | 모델 API / MCP / 좁은 범위 모델 |
| API·이벤트 계약 | Protobuf/OpenAPI 등 명세 | 명세·생성 관계·호환성 검사 결과 |
| 결정 이유·트레이드오프 | ADR | 관련 프로젝트·결정 ID로 검색 |
| 배포 버전·환경 | 배포 매니페스트와 배포 시스템 | 환경별 상태 조회 |
| 변경 중인 코드 | 현재 worktree | 로컬 원문·현재 그래프 |

Nx는 MCP 참조 문서가 있고, Turbo는 GraphQL query, Bazel은 query/cquery/aquery, Pants는 introspection/JSON, Buck2는 BXL 접근을 제공한다. 따라서 에이전트 친화성은 MCP 로고 유무보다 **어떤 사실을 어떤 범위·근거·구조로 반환하는가**로 비교해야 한다. ([Nx MCP](https://nx.dev/docs/reference/nx-mcp), [Turbo query](https://turborepo.dev/blog/2-9), [Bazel query](https://bazel.build/query/guide), [Pants introspection](https://www.pantsbuild.org/stable/docs/using-pants/project-introspection), [Buck2 BXL](https://buck2.build/docs/bxl/))

LikeC4도 자체 AI 도구·MCP와 모델 API를 제공한다. 필요 정보가 이미 조회되는지 먼저 확인하고, 별도 통합 계층은 ID 연결·권한·조회 범위·출처를 보완하는 데 집중하는 편이 낫다. ([LikeC4 AI Tools](https://likec4.dev/tooling/ai-tools/), [Model API](https://likec4.dev/tooling/model-api/))

### 권고하는 중앙 조회 흐름

1. 루트 AGENTS.md는 전사 백과사전 대신 탐색 안내와 공통 제약을 담는다.
2. 프로젝트 ID로 소유자·경로·빌드 타깃·계약·ADR 링크를 조회한다.
3. 변경된 파일의 소유 프로젝트와 직접 영향 관계를 구한다.
4. 필요한 경우에만 역의존성·관련 계약·관련 ADR을 확장한다.
5. 실행한 분석의 근거 경로·source revision·관계 종류를 응답에 남긴다.

중앙 색인에는 최소한 project ID, entity ref, architecture element ID, source URI/path, source revision, 관계 유형, 추출 시점, 추출기 버전을 기록하도록 권고한다. 이름이 같다는 이유로 관계를 자동 연결하지 않는다. 하나의 Backstage component가 여러 build target을 가질 수 있으므로 1:1 대응도 강제하지 않는다.

중앙 시스템이 main의 커밋을 색인했다고 현재 작업 브랜치를 정확히 아는 것은 아니다. **전역 탐색은 중앙 색인, 현재 변경 판단은 로컬 worktree**를 우선하고 revision 차이를 드러내야 한다. 이 구분은 모노레포·polyrepo 모두에 적용되는 설계 권고다.

벡터 검색은 “왜 이런 결정을 했나” 같은 문서 탐색에 보조적으로 쓸 수 있다. 그러나 “이 파일 변경 시 어떤 타깃을 반드시 테스트해야 하나”는 가능한 한 실제 dependency graph와 명시적 관계에 근거해야 한다. 자연어 검색의 관련성과 빌드 영향의 완전성은 서로 다르다.

### 중앙집중의 범위

중앙에는 schema·정책·ID 규칙·조회·검증을 둔다. 서비스 팀은 코드 옆의 catalog/model/ADR을 유지한다. Backstage의 코드와 함께 저장하는 메타데이터 모델이 이 방식과 맞는다. ([Backstage catalog](https://backstage.io/docs/features/software-catalog/))

권한 경계가 필요한 경우에는 저장소 구성을 별도로 판단한다. CODEOWNERS는 리뷰 책임을 지정하는 기능이며 파일별 읽기 격리를 대신하는 장치로 쓰면 안 된다. ([GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners))

현재 대화에서 검증했던 Nx MCP 동작은 문서 검색 응답이었다. 그것만으로 bunsik의 모든 프로젝트 조회·그래프·CI 관련 MCP 기능까지 검증한 것으로 간주하지 않는다. 실제 에이전트 조회를 구성할 때는 서버가 노출한 기능과 현재 저장소 데이터를 별도로 확인해야 한다.

## 15. 비용 비교: 제품 요금보다 총운영비

아래는 비용 추정을 위한 틀이며 실측 결과가 아니다.

**기간별 총비용 = 도입·전환 비용의 배분 + 도구/서비스 요금 + CI/캐시/전송 비용 + 플랫폼 유지 시간 + 개발자 대기·장애 진단 비용.**

“오픈소스라 무료”는 서비스 운영비와 인건비를 제외한 표현이다. 반대로 관리형 서비스 요금이 있어도 자체 운영과 대기 시간을 충분히 줄이면 총비용은 낮아질 수 있다. Nx Cloud의 현재 가격표도 credit·compute·기여자/연결 등 플랜별 요소를 확인해야 하므로 단순 VM 단가만으로 비교하면 불완전하다. ([Nx 가격표](https://nx.dev/pricing))

| 선택 | 초기 비용이 생기는 곳 | 지속 비용이 생기는 곳 |
|---|---|---|
| Nx | 기존 프로젝트 등록·플러그인·입력/출력 정리 | 플러그인 업그레이드·그래프 회귀·Cloud 또는 자체 캐시 |
| Turbo | workspace/task wrapper·출력/환경 모델 | 비JS 관계 동기화·릴리즈 조합·CI 분할 |
| Bazel | BUILD·rules·toolchain·IDE·기존 빌드 전환 | rules 호환성·원격 서버·target 설계·개발자 지원 |
| Buck2 | BUCK·prelude·toolchain·BXL/IDE 연결 | 내부 플랫폼 코드·외부 ecosystem gap·worker 관리 |
| Pants | BUILD/source roots/resolve·테스트 환경 정리 | 추론 예외·실험 backend·lockfile·패키징 조건 |
| Native + CI | 공통 명령·CI template·서비스 manifest | 언어간 영향 분석·예외·표준 준수·수동 동기화 |
| Domain repos + 중앙 플랫폼 | ID·카탈로그·표준 pipeline·계약 버전 규칙 | cross-repo 변경 배포·버전 전파·중앙 색인 |

이 표는 상대적 작업 위치의 비교다. 도구별 전담 인원 수나 월비용에 보편적인 숫자를 붙일 공개 근거는 확보하지 못했다. 또한 현재 bunsik은 실제 서비스 workload가 없으므로 특정 도구의 절감률을 계산할 수 없다.

## 16. 선택 전에 실행할 비교 실험

모든 후보를 설치하는 대규모 실험보다, 언어 구성을 정한 뒤 유력한 두 후보와 네이티브 기준선을 비교하는 것이 효율적이다. 다음은 제안된 실험이며 이 조사에서 실행하지 않았다.

### 대표 workload

단일 hello-world 서비스가 아니라 **공통 schema + 서로 다른 언어의 소비자 두 개 + 공통 라이브러리 + 단위/계약 테스트 + OCI 이미지**를 준비한다. 그래야 언어간 연결에서 얻는 가치와 추가 비용을 측정할 수 있다.

### 변경 시나리오와 정답

| 시나리오 | 확인할 것 |
|---|---|
| 깨끗한 머신의 최초 실행 | 도구 다운로드·의존성 설치·전체 빌드 시간 |
| 변경 없는 재실행 | 그래프 분석·캐시 조회·artifact 복원 overhead |
| 서비스 내부 구현만 변경 | 해당 서비스와 실제 영향 범위만 검증하는가 |
| 공유 라이브러리 변경 | 전이 소비자가 누락되지 않는가 |
| 공통 schema 변경 | 모든 언어 codegen·소비자 검증이 연결되는가 |
| compiler/runtime/lockfile 변경 | 환경 변화가 올바르게 무효화되는가 |
| 환경변수·resource 파일 변경 | stale cache hit가 발생하지 않는가 |
| 파일 이동·삭제 | 기존 의존성·생성물·stale output을 올바르게 처리하는가 |
| 원격 캐시 장애 | 실패 정책·fallback·원인 설명이 명확한가 |
| 개발 머신과 CI의 OS/architecture 차이 | 지원 조합에서 빌드·캐시가 안전한가 |
| 구버전 consumer와 새 provider | 한 커밋 컴파일과 별도로 배포 호환성을 검증하는가 |
| 에이전트 프로젝트 조회 | 소유자·타깃·영향 경로·ADR을 정확하고 짧게 반환하는가 |

실행 대상을 사람이 정의한 기대 관계와 비교해야 한다. 캐시를 끈 clean 결과와 warm 결과의 동등성도 검사한다. 실행을 놓치지 않는 것이 우선이고, 이후 불필요한 실행을 줄인다.

### 측정 항목

- PR 피드백 시간 p50/p95와 최초 실패를 발견하는 시간
- 전체 CPU 시간과 원격 작업자의 대기·준비 시간
- cache hit/miss 및 artifact 다운로드 bytes
- dependency 설치·그래프 분석·테스트 실행을 구분한 시간
- 생성 코드의 IDE 탐색·디버깅·테스트 재현 성공 여부
- 새 서비스를 추가하고 toolchain을 갱신하는 데 든 실제 작업 시간
- 잘못된 실행 누락, 불필요 재실행, 캐시 불일치의 건수
- 에이전트의 잘못된 프로젝트 선택·명령 추측·출처 누락
- 사용자 정의 glue·plugin·rules의 유지 주체와 수정 빈도

“Bazel은 몇 배 빠르다”, “Nx면 CI가 몇 % 줄어든다”는 수치보다 이 저장소의 반복 변경 패턴에서 순편익이 있는지가 선택 기준이다.

## 17. bunsik에 대한 권고

앞선 답변의 “현재 Nx를 바꿀 근거가 없다”는 말은 **Nx가 최적이라는 검증**이 아니라, 당시 교체 근거가 없었다는 뜻으로 한정해야 한다. 실제 언어·서비스 구성·CI workload가 없는 상태에서는 최종 순위를 정할 수 없다.

현재 조건에서 권고하는 방향은 다음이다.

1. **Backstage·LikeC4·ADR·공통 ID와 조회 구조를 먼저 빌드 도구와 독립적으로 설계한다.** 이 투자는 Nx를 유지해도 교체해도 남는다.
2. **네이티브 언어 도구를 기준선으로 둔다.** 패키지 해석·IDE·서비스 패키징이 실제로 필요한 형태로 동작하게 한다.
3. **Nx는 얇은 프로젝트·작업·조회 통합 후보로 유지한다.** 모든 언어의 세부 빌드를 Nx 설정으로 재작성하지 않는다.
4. **공통 계약과 다언어 소비자에서 비용을 검증한다.** 생성·검증·조회 연결이 단순하면 얇은 통합으로 충분할 수 있다.
5. **정밀한 빌드 모델의 추가 이익이 확인될 때 Bazel/Pants/Buck2를 선택한다.** 회사 크기나 예상 서비스 수만으로 결정하지 않는다.

| 실제로 확정되는 조건 | 우선 비교할 조합 |
|---|---|
| TS/Node 중심 + JVM/.NET 혼합 | Nx + native builds 대 native + CI |
| JS workspace 중심, 소수 독립 비JS 서비스 | Turbo 대 얇은 Nx |
| Python 중심, 공유 패키지·테스트·버전 충돌이 큼 | Pants 대 uv + native tests + CI |
| 여러 컴파일 언어와 codegen·공유 소스가 깊게 연결 | Bazel 대 native 상위 통합, Buck2는 toolchain 조건 충족 시 |
| 서비스들이 독립적이며 CI 환경 차이가 주된 병목 | Dagger/Bake + native 대 Nx + 컨테이너 작업 |
| 권한·조직·릴리즈 독립성이 저장소 원자성보다 중요 | 도메인별 모노레포/polyrepo + 중앙 지식·정책 |

특히 MSA에서 런타임 관계가 복잡한 것과 빌드 그래프가 복잡한 것은 다르다. **런타임 복잡성에는 계약·관측·배포 정책이, 빌드 복잡성에는 정확한 입력 그래프와 실행 엔진이 필요하다.** 어느 쪽이 실제 병목인지 먼저 나누는 것이 과도한 도구 도입을 줄인다.

## 18. 조사 한계와 최신성

이 보고서는 도입·기능·제약을 판단하는 문헌 조사다. 저장소별 동일 조건 벤치마크, 기업별 전체 인건비, 공개되지 않은 내부 서비스 구조는 확인하지 못했다.

- 기업 성공사례는 실제 사용의 근거지만 선택 편향·공급자 관점이 있다.
- 기업·대형 오픈소스·MSA 데모·튜토리얼을 구분했다. 특히 전용 모노레포 도구가 없는 대기업 전사 다언어 MSA의 완전한 인프라 공개 사례는 제한적이다.
- 문서에 특정 도구가 등장하지 않는다는 것만으로 기업 전체에서 사용하지 않는다고 결론내리지 않았다.
- 같은 이름의 “지원”도 official/community/experimental, 언어 인식/의존성 추론/toolchain 설치를 나눴다.
- Nx 캐시 패키지의 2026-05-21 변경, Turbo query의 2026-03-30 stable 전환, Earthly의 2025년 종료 공지는 과거 추천과 충돌하므로 최신 원문을 우선했다.
- Pants stable 문서는 조사 시 2.33, Nx 문서는 v23, moon 문서는 v2를 표시했다. 도입 시 고정 버전의 문서와 플러그인 상태를 다시 확인해야 한다.
- Windows/macOS/Linux, CPU architecture, 프레임워크·IDE의 모든 조합은 직접 검증하지 않았다.
- 도구 가격은 계약·플랜·사용량에 좌우되므로 확정 월비용을 제시하지 않았다.
- 조사 범위의 핵심 주장·반례·선택 조건에 근거가 확보되어 추가 일반 검색을 종료했다. 남은 중요한 불확실성은 공개 자료를 더 모으는 것보다 실제 workload 실험으로 해결하는 편이 낫다.

Markdown 보고서의 구조·링크 형식·파일 내용을 검증했다. 별도 PDF/HTML 렌더링 및 화면 검사는 수행하지 않았다.

## 19. 추가 질문: Bazel의 commitlint와 Git hook 구성

Bazel은 빌드·테스트 엔진이고 Git hook의 설치·트리거는 Git 또는 hook manager가 맡는다. 권고 조합은 **Lefthook + commitlint + Bazel 검사 타깃 + CI 필수 검사**다. JS 중심 저장소에서는 Husky도 가능한 선택이다. Lefthook은 독립 바이너리로도 배포하므로 npm을 hook manager 자체의 필수 조건으로 삼지 않아도 된다. 다만 아래 예시는 commitlint용 Node 도구를 npm으로 설치하는 구성이다. ([Git hooks](https://git-scm.com/docs/githooks), [Lefthook 설치](https://lefthook.dev/install/), [commitlint local setup](https://commitlint.js.org/guides/local-setup))

예시 설치 명령(이 저장소에서 실행하지 않음):

    npm install --save-dev --save-exact lefthook @commitlint/cli @commitlint/config-conventional

루트 commitlint.config.cjs:

    module.exports = {
      extends: ['@commitlint/config-conventional'],
    };

루트 lefthook.yml:

    commit-msg:
      jobs:
        - name: commitlint
          run: npx --no -- commitlint --edit "{1}"

설정 후 hook을 설치한다.

    npx --no -- lefthook install

Lefthook의 {1}은 Git hook의 첫 번째 인자이며, commit-msg에서는 커밋 메시지 파일 경로다. 설정 파일은 Git으로 공유하고 각 clone의 bootstrap에서 hook 설치를 수행한다. npm postinstall 동작에만 의존하기보다 bootstrap 절차에 설치를 명시하면 설치 경로를 파악하기 쉽다. Node·npm·도구 버전과 lockfile도 고정한다. ([Lefthook 인자 치환](https://lefthook.dev/configuration/run/), [Lefthook install](https://lefthook.dev/usage/commands/install/), [commitlint 설정](https://commitlint.js.org/reference/configuration.html))

역할 분담은 다음처럼 권고한다.

| 위치 | 권고 작업 |
|---|---|
| commit-msg | 현재 메시지 검사 |
| pre-commit | 빠른 포맷·lint, staged 상태 처리 검토 |
| pre-push | 필요한 경우 좁은 범위 Bazel 테스트 |
| CI | PR commit 범위 또는 squash 정책에 맞춘 최종 메시지 검사, 필수 Bazel 검증 |

Bazel로 commitlint 실행 자체를 통일하고 싶으면 실행 가능한 wrapper target을 만들고 bazel run으로 호출할 수 있다. 다만 hook의 메시지 파일은 worktree의 외부 상태이므로 파일 경로·실행 cwd를 처리해야 한다. bazel run은 BUILD_WORKSPACE_DIRECTORY 등 실행 환경 정보를 제공한다. **미선언 .git 파일을 읽는 캐시 가능한 일반 build/test action으로 모델링하지 않는 것**이 안전한 설계다. ([Bazel run 설명](https://bazel.build/docs/user-manual))

로컬 hook은 우회할 수 있으므로 규칙 강제는 CI와 merge 조건에서 수행한다. commitlint 공식 CI 가이드는 PR의 base/head 범위 검사와 필요한 Git history 확보를 설명한다. Squash merge 정책이면 PR 제목·최종 squash 메시지 규칙도 함께 정해야 한다. ([commitlint CI setup](https://commitlint.js.org/guides/ci-setup.html))

