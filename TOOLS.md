| 영역                                   | 대표 툴                                             | 역할                                                      |
| ------------------------------------ | ------------------------------------------------ | ------------------------------------------------------- |
| **Architecture Model**               | **LikeC4**, Structurizr                          | 시스템/서비스/컴포넌트/관계/배포/동적 흐름                                |
| **Architecture Decision**            | **MADR**, adr-tools, Log4brains                  | ADR, 결정·대안·Trade-off                                    |
| **RFC / Design Proposal**            | GitHub/GitLab RFC repo, Confluence               | 구현 전 큰 설계 변경 제안·검토                                      |
| **Domain Modeling**                  | **Context Mapper**                               | Domain/Subdomain/Bounded Context/Context Map            |
| **Distributed Architecture Catalog** | **EventCatalog**                                 | Domain/System/Service/API/Event/Flow/Owner              |
| **Developer/System Catalog**         | **Backstage**, Port, Cortex, OpsLevel            | System/Service/API/Resource/Owner/Repo 탐색               |
| **HTTP Contract**                    | **OpenAPI**                                      | REST/HTTP 계약                                            |
| **Event Contract**                   | **AsyncAPI**                                     | 메시지/Event 계약                                            |
| **RPC/Schema**                       | **Protobuf + Buf**                               | RPC 계약, schema breaking 검증                              |
| **Schema Registry**                  | **Apicurio Registry**, Confluent Schema Registry | Event/API schema 버전·호환성 관리                              |
| **Architecture Fitness / Policy**    | **ArchUnit**, NetArchTest, OPA/Conftest          | 아키텍처 규칙을 CI에서 실제 강제                                     |
| **Security Architecture**            | **OWASP Threat Dragon**, pytm                    | Threat Model / Trust Boundary / Threat                  |
| **Runtime / Observability**          | OpenTelemetry + Grafana 계열                       | 실제 runtime dependency/trace/운영 현실                       |
| **Repo Knowledge**                   | **OpenWiki**                                     | 코드에서 구현 구조·행동·근거 지식 추출                                  |
| **AI/Shared Knowledge**              | OpenKnowledge 등                                  | Git 기반 AI 검색/작성/지식 접근                                   |
| **Docs Portal**                      | MkDocs, **Backstage TechDocs**, Docusaurus       | Markdown 문서 검색/게시                                       |
| **Knowledge Format**                 | **OKF**                                          | Markdown 지식 metadata/provenance/lifecycle 포맷 — **툴 아님** |
| **Data Architecture**                | **DataHub**, OpenMetadata                        | Data catalog/ownership/lineage                          |
| **Enterprise Architecture**          | Sparx EA, Ardoq, LeanIX 등                        | Business→Application→Technology 전사 EA                   |
