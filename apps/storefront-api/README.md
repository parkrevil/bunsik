# storefront-api

쇼핑몰 백엔드. Bun 런타임에서 도는 NestJS 애플리케이션이다.

| | |
|---|---|
| 런타임 | Bun 1.4.2 |
| 프레임워크 | NestJS 12 (`@nestjs/platform-express`) |
| 언어 | TypeScript 7 (네이티브 Go 컴파일러), ESM |
| 테스트 | `bun test` |
| 린트·포맷 | oxlint · oxfmt |

Nest CLI 는 쓰지 않는다. TypeScript 7.0 이 programmatic compiler API 를 제공하지
않아 `nest build`/`start`/`generate` 가 전부 동작하지 않기 때문이다. 빌드는
`bun build --compile`, 타입 체크는 `tsc --noEmit` 이 담당한다.

## 명령

```bash
bun run dev           # 개발 서버 (소스 직접 실행, 파일 변경 감지)
bun run build         # 단일 실행 파일 → dist/server
bun run start         # 빌드된 바이너리 실행

bun run typecheck     # tsc --noEmit
bun run lint          # oxlint
bun run format        # oxfmt (쓰기)
bun run format:check  # oxfmt --check (쓰지 않고 검사만)

bun run test          # 단위 테스트
bun run test:e2e      # e2e 테스트
bun run test:all      # 전부
```

## 빌드 산출물

`bun run build` 는 `node_modules` 없이 단독 실행되는 바이너리를 만든다.

- `--bytecode` — 파싱을 빌드 시점으로 옮긴다 (기동 101ms → 54ms)
- `--format=esm` — `src/main.ts` 의 최상위 `await` 때문에 필수다. TLA 를 걷어내면 이 플래그도 불필요해진다
- `--sourcemap=inline` — 없으면 스택트레이스가 `/$bunfs/root/...` 로만 찍힌다. 기동 영향 없음
- `--no-compile-autoload-bunfig` / `--no-compile-autoload-dotenv` — 바이너리가 실행 디렉터리의
  `bunfig.toml`·`.env` 를 읽지 않게 한다. `bunfig.toml` 의 `preload` 는 실행 디렉터리에서만
  읽히므로 그대로 두면 임의 코드 실행 경로가 된다. **환경변수는 정상 동작한다** — 파일만 무시한다
- `--minify-identifiers` 는 쓰지 않는다. DI 는 깨지지 않지만 Nest 로그 라벨이
  `[InstanceLoader]` → `[Vi]` 로 뭉개지고 (`--keep-names` 로도 못 막는다) 이득은 0.4% 뿐이다

## 의존성 패치

`patches/` 참조. `bun build --compile` 이 NestJS 의 optional peer dependency 에서
멈추는 문제를 `bun patch` 로 해결한다.
