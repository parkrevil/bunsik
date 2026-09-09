# 물류 프로젝트

이 프로젝트는 Agentic Workflow, Multi-platform Frontend, Backend, DevOps, Data, LLM, ML 등 현대적인 소프트웨어 시스템 전반의 기술 스택을 실제 서비스 수준에서 경험하기 위한 프로젝트다.

먼저 각 영역에서 학습·검증할 기술 스택을 선정하고, 해당 기술들을 억지 없이 모두 적용할 수 있으며 대규모 트래픽과 엔터프라이즈 확장성을 가질 수 있는 서비스 도메인을 선정하여 전체 시스템을 설계·구현한다.

## Services

백오피스는 OMS / WMS / TMS / SCP 네 개의 시스템으로 나뉜다. 고객은 시스템 단위로 구독하며, 각 시스템은 단독으로도 사용 가능하고 함께 구독하면 연결되어 동작한다.

### 쇼핑몰
고객이 상품을 탐색·구매하는 자사몰. 백오피스 시스템이 아니라 판매 채널이며, 구독 단위에 포함되지 않는다.
주문을 발생시켜 OMS로 넘기고, OMS 미구독 시에는 WMS로 직접 넘긴다.

- 구성 요소는 Architecture 섹션 참조 (Product / Payment / Promotion / Gift / Shopping Auth / Shopping Website)

### OMS — Order Management System
주문 수집·오케스트레이션과 이행 경로 결정

- Order Capture — 멀티채널 주문 수집
- DOM — Distributed Order Management (소싱·출고지 결정)
- Availability — ATP 가용재고, 예약, 채널 배분
- Omnichannel — BOPIS, Ship-from-Store
- RMS — Returns Management System (반품 정책·교환·환불. 물리 입고는 WMS)
- CSR Console

### WMS — Warehouse Management System
창고 내 재고의 물리적 관리와 작업 실행

- Inbound — ASN, 검수, Putaway
- Storage — 로케이션, 슬로팅, 보충, 실사
- Outbound — 할당, 웨이브, 피킹, 패킹, 상차
- Stock — LPN, Lot/Serial, 유통기한, 재고 원장
- Returns Receiving — 반품 입고·검사·재입고 분기
- WES — Warehouse Execution System
- WCS — Warehouse Control System
- LMS — Labor Management System
- YMS — Yard Management System
- 3PL — 화주별 재고 분리, 정산, 화주 포털

### TMS — Transportation Management System
화물 이동의 계획·조달·실행·정산

- Planning — 오더 통합, 로드 빌딩, 배차
- Routing — 경로 최적화
- Rating — 운임 산출
- Tendering — 캐리어 선정·의뢰
- Execution — 추적, ETA, 예외
- Freight Settlement — 운임 정산·감사, 클레임
- Carrier Management System
- FMS — Fleet Management System
- Last-mile — 기사앱, 동적 배차, POD
- GTM — Global Trade Management

### SCP — Supply Chain Planning
수요 예측과 그에 따른 공급·재고 계획

- Demand Planning
- Replenishment Planning
- Allocation Planning
- S&OP / IBP
- SRM — Supplier Relationship Management
- Procurement Management System — 발주, 납기 관리, 입고예정 발행, 매입정산

### Supply Chain Control Tower
시스템 경계에서 발생하는 예외를 감지·알림한다. 2개 이상 구독 시 활성화되며, 활성 규칙은 구독 조합에서 파생된다.

- 예외 규칙
- 알림
- 통합 조회


## Architecture
### Shopping Web BFF
쇼핑몰 웹 화면 전용 API 서버. 화면에 필요한 정보를 여러 서비스에서 모아 하나의 응답으로 제공하고,
이 화면에서만 쓰이는 요청 흐름을 관장

- BFF는 화면(클라이언트) 단위로 둔다. PC·모바일 앱이 추가되면 해당 클라이언트용 BFF를 별도로 만든다

- Bun, Nestjs

### OMS Web BFF
OMS 웹 화면 전용 API 서버. 주문 운영 화면의 요청을 처리하고 주문·가용재고·반품 관련 서비스를 조합

- Bun, Nestjs

### WMS Web BFF
WMS 웹 화면 전용 API 서버. 창고 작업 화면의 요청을 처리하고 입출고·재고·작업 관련 서비스를 조합

- Bun, Nestjs

### TMS Web BFF
TMS 웹 화면 전용 API 서버. 운송 화면의 요청을 처리하고 배차·운임·추적 관련 서비스를 조합

- Bun, Nestjs

### SCP Web BFF
SCP 웹 화면 전용 API 서버. 계획 화면의 요청을 처리하고 예측·보충·발주 관련 서비스를 조합

- Bun, Nestjs

### Control Tower Web BFF
컨트롤타워 웹 화면 전용 API 서버. 각 시스템이 발행한 정보로 만든 조회용 데이터를 제공하며 쓰기는 담당하지 않음

- Bun, Nestjs

### Item Master
구매·보관·재고·운송·판매의 기준이 되는 품목 마스터 정보를 관리

### Product
품목을 고객에게 판매하기 위한 상품 정보와 판매 구성을 관리

### Order
고객의 구매 주문과 주문 상태·변경·취소 등의 주문 생명주기를 관리

### Inventory
품목의 위치·상태별 수량과 가용성을 관리

- Stock / Reservation / Availability / Ledger

### Warehouse
재고가 보관되는 물리적 공간과 운영상 위치 그룹을 관리
- Site / Warehouse / Aisle / Rack / Location / Zone

### Shopping Website
고객이 상품을 탐색·구매하고 주문·회원 정보를 이용하는 쇼핑 사용자용 웹 애플리케이션

- Bun / Next.js

### Shopping Auth
쇼핑 고객의 가입·인증과 본인 정보 접근 권한을 담당. 고객이 직접 가입하며 계정은 쇼핑몰에만 속함
- Role / Permission
- 이메일(아이디) / Password / Passkey / Google / Apple / 네이버 / 카카오

### Backoffice Website
운영자가 상품·주문·재고·창고 등 시스템 전반을 관리하는 백오피스용 웹 애플리케이션

- Bun / Angular SPA

### Backoffice Auth
운영자 인증과 역할·권한 관리를 담당. OMS / WMS / TMS / SCP / 컨트롤타워가 공통으로 사용하며,
여러 시스템을 구독한 고객도 한 번의 로그인으로 전부 이용
- 계정은 관리자가 발급하고 고객사(테넌트)에 소속됨
- Role / Permission — 조직·사이트·시스템 단위로 부여
- 아이디(일반 아이디, 이메일 안임) / Password / Passkey / SSO
- SSO는 고객사가 이미 쓰는 인증 체계에 연결해 사용

### Payment
쇼핑 주문 및 기타 결제의 승인·확정·취소·환불과 외부 결제수단 연동을 관리

### Billing
SaaS 이용에 대한 요금제·구독·사용량·청구와 반복 과금을 관리

### Promotion
구매·회원·상품·채널 등의 조건을 평가하여 적용 가능한 혜택을 결정

### Gift
프로모션 또는 별도 지급 정책에 따라 사은품 후보를 평가하고 지급 대상을 선정

## Agentic Workflow
다음은 후부군들이다. 각 항목을 다양한 환경에서 실제로 테스트해보고 조합하면서 최적의 조합을 찾아야한다.
이걸 어떻게 찾을지도 시나리오 필요. 어떤 내용들이 문서에 담기는지도 확인 필요.

## AI Frameworks
- LangGraph
- Google ADK
- Microsoft Agent Framework
- Mastra
- Agno
- CrewAI

## Harness

### 적용 주제
- 개발
- 운영/모니터링
- 고객 전용 비서 에이전트

### Frameworks
- Lang?????
- Google ADK
- Microsoft AI Framework

### Plugins
- Superpowers
- gstack
- GSD
- Spec kit

### Documentation
#### 최상위 지식
- Backstage
- EventCatalog
- Structurizr

#### 서비스별 지식
- openwiki: 모든 서브 프로젝트에 공통 적용
- Google Conductor
- OpenSpec
- Spec Kit
- Agent OS
- Tessl
- OKF

### Harness


## Frontend
### Web

### Web for AI
인간용 UI가 없는 AI용 정보만 제공.
구글에서 크롬에 해당 기능을 구현하고 있는것으로 알고있음. 리서치 필요
WebMCP도 리서치 필요.
A2A도 참고.

### PC
### Mobile
## Backend

## Data
### Search / Retrieval
- Elasticsearch
  - Full-text Search
  - Product Search
  - Semantic / Vector Search
  - Hybrid Search
  - RAG Retrieval

## DevOps

- Multi Tenant

### Local Cluster — Argo
- Kubernetes
  - kind
  - Cilium
  - Gateway API
- Argo CD
- Helm
- Kustomize
- Vault
- Vault Secrets Operator
- cert-manager
  - Vault PKI
- Kyverno
- OpenTelemetry
- Prometheus
- Thanos
- Loki
- Jaeger

### Local Cluster — Flux
- Kubernetes
  - kind
  - Calico
  - Gateway API
- Flux
- Helm
- Kustomize
- OpenBao
- External Secrets Operator
- Secrets Store CSI Driver
- cert-manager
  - OpenBao PKI
- OPA Gatekeeper
- OpenTelemetry
- VictoriaMetrics Cluster
- OpenSearch
- Tempo

### Shared
- Docker Desktop
- Terraform
- GitHub Actions
  - Self-hosted Runner
- Harbor
- Vault
  - Central Secret Manager
- Grafana Mimir

## LLMOps
## MLOps



