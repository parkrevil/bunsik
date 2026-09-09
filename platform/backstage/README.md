# [Backstage](https://backstage.io)

프로젝트 개발자 포털. `@backstage/create-app@0.9.1`의 기본 템플릿으로 생성했다.
제품 앱과 독립적인 Yarn workspace이며 `packages/backend`는 Backstage 자체 API 서버다.

이 디렉터리에서 실행한다. nvm이 로드된 셸을 사용한다.

```sh
nvm use
corepack enable
yarn install --immutable
yarn start
```

웹: http://localhost:3000 / 서버: http://localhost:7007

기존 설치 그대로 Bun에서 실행하려면, 이 디렉터리에서 아래 패치를 한 번 적용한다.
의존성을 재설치해 패치가 사라지면 다시 적용한다. 기존 버전·Yarn lockfile·SQLite 설정을 유지한다.

```sh
patch --dry-run --batch --forward -p1 -d node_modules -i ../bun.patch
patch --batch --forward -p1 -d node_modules -i ../bun.patch
bun --bun run start
```

`bun.patch`는 SQLite 드라이버를 `bun:sqlite`로 연결하고, 연결 옵션·조회 판정·외래키 초기화와
인증키 내보내기를 호환시킨다. 공식 Bun 지원이 아닌 로컬 호환 패치다.
Bun 1.4.2에서 타입 검사·전체 빌드·로그인·카탈로그/액션 조회·잘못된 토큰 거부와
SQLite CRUD·트랜잭션/롤백·외래키·스키마 변경·직렬화를 검증했다. Docker는 기존 Node 구성을 유지한다.
근거: [Bun SQLite](https://bun.com/docs/runtime/sqlite),
[Knex 드라이버 소스](https://github.com/knex/knex/blob/3.1.0/lib/dialects/better-sqlite3/index.js).

```sh
yarn tsc
yarn build:backend
```

- 실행 버전: Node 26.8.1, 템플릿에 포함된 Yarn 4.13.0.
- 공식 생성기는 Node 26을 거부하므로 생성만 Node 24.21.0에서 `--skip-install`로 수행했다.
- Bun 1.4.2의 `bunx --bun`도 Node 호환 버전 26 검사에서 거부됐다.
- Node 26.8.1에서 설치·타입 검사·백엔드/프런트엔드 번들 빌드와 개발 서버 HTTP 200을 확인했다.
- upstream의 공식 Node 지원은 22/24다. 이 프로젝트의 `engines.node`에 26을 추가한 것은 로컬 검증에 따른 선택이다.
- Dockerfile의 Node도 26.8.1로 맞췄다. 컨테이너 이미지 빌드·실행은 아직 검증하지 않았다.
- 초기 생성 lockfile은 첫 `yarn install`에서 갱신했다. 이후에는 `--immutable`을 사용한다.
- 템플릿의 peer dependency 경고가 남아 있다. 외부 인증·운영 DB를 설정한 운영 배포가 아닌 로컬 기본 설치다.

다른 앱은 자체 `.nvmrc`와 의존성을 사용한다. nvm은 디렉터리 이동만으로 자동 전환되지 않으므로
각 디렉터리에서 `nvm use`하거나 `nvm exec <version> <command>`로 실행한다.
Bazel은 `.nvmrc`를 자동으로 적용하지 않는다. 향후 실행 타깃에서도 Node 버전을 명시해야 한다.

근거: [공식 설치](https://backstage.io/docs/getting-started/),
[Node 지원 정책](https://backstage.io/docs/overview/versioning-policy/#nodejs-releases),
[공식 컨테이너 빌드](https://backstage.io/docs/deployment/docker/),
[Bun 실행 방식](https://bun.com/docs/pm/bunx).
