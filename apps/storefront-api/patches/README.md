# patches

## `@nestjs/core` · `@nestjs/common` — `bun build --compile` 대응

NestJS 는 마이크로서비스·웹소켓·검증 파이프를 optional peer dependency 로 두고
`optionalRequire(name, () => import(name))` 형태로 동적 로드한다.

Bun 번들러는 해석되지 않는 `import()` 를 견딜 수 있지만, 조건이 있다 —
**`import()` 가 `try` 블록 안에 렉시컬하게 있고 그 자리에서 `await` 될 것.**
파서(`src/js_parser` 의 `try_body_count`)가 그때만 `HANDLES_IMPORT_ERRORS` 를 세우고,
`src/bundler/bundle_v2.rs` 의 resolve 실패 분기가 하드 에러 대신 통과시킨다.

NestJS 는 `import()` 를 화살표 함수에 담아 넘기고 `try` 는 호출된 쪽에 두므로
이 조건을 만족하지 못해 `Could not resolve: "@nestjs/microservices"` 로 빌드가 멈춘다.
Bun 의 결함도 NestJS 의 결함도 아닌 형태 불일치다.

이 패치는 `@nestjs/core`·`@nestjs/common` 의 10개 호출부를 다음 형태로 바꾼다.

    () => import('X')
    → async () => { try { return await import('X'); } catch (e) { throw e; } }

예외를 그대로 다시 던지므로 NestJS 의 원래 동작이 보존된다. `class-validator`
없이 `ValidationPipe` 를 쓰면 원문 그대로 출력된다 —
`The "class-validator" package is missing. Please, make sure to install it to use ValidationPipe.`

- 상류 수정: oven-sh/bun#35467 (OPEN, 미머지). 머지되면 이 패치는 제거한다.
- 관련 이슈: oven-sh/bun#4803, #11836, #14611, #14676
- **NestJS 업그레이드 시 재적용·재검증이 필요하다.** 패치가 깨지면 `bun run build` 가
  `Could not resolve` 로 죽으므로 빌드가 곧 회귀 감지 수단이다.

### 패치 범위 밖

`@nestjs/testing/testing-module.js:22,23` 에도 동일한 패턴이 2곳 있다(전체 12곳).
테스트는 소스에서 실행하므로 `--compile` 을 타지 않아 패치하지 않았다. 테스트를
바이너리로 빌드하게 되면 이 2곳도 패치 대상이 된다.

## 이 패치로 고쳐지지 않는 경로 — `loadPackageSync`

`@nestjs/common/utils/load-package.util.js` 의 `loadPackageSync` 는 `import()` 가
아니라 **동기 `createRequire(import.meta.url)(packageName)`** 를 쓴다. try/await
패치 기법이 닿지 않으며, 컴파일 바이너리에서는 원천적으로 실패한다.

    소스 실행     : import.meta.url = file:///.../src/x.ts   → createRequire OK
    컴파일 바이너리 : import.meta.url = file:///$bunfs/root/…  → Cannot find module 'rxjs'

`/$bunfs` 가상 파일시스템 기준으로 해석되므로 **번들에 이미 포함된 패키지조차**
찾지 못한다. 도달 경로는 `loadPackageCached(name, context)` 가 캐시 미스로
`loadPackageSync` 로 폴백하는 지점(`load-package.util.js:70`), 즉
`connectMicroservice()` 계열이다.

현재 앱은 마이크로서비스를 쓰지 않아 도달하지 않는다. **마이크로서비스를 도입하면
`--compile` 바이너리에서 별도 검증이 필요하다.**
