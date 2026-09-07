"""룰 사이에 오가는 provider 정의."""

BunInfo = provider(
    doc = "Bun 실행 파일을 호출하는 방법.",
    fields = {
        "bun": "Bun 실행 파일 File. 액션에서는 `executable`/`tools` 로 넘긴다.",
        "version": "Bun 버전 문자열. 분석 단계에서 버전별 분기에 쓴다.",
        "tool_files": "runfiles 에 넣어야 하는 파일들.",
    },
)
