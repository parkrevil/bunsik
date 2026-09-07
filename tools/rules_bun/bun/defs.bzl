"""공개 API. 소비자는 이 파일만 load 한다.

`//bun/private/...` 는 내부 구현이며 외부에서 참조하지 않는다.
"""

load("//bun/private:providers.bzl", _BunInfo = "BunInfo")

# 룰 작성자가 `toolchains` 속성에 넣는 툴체인 타입.
# 문자열이 아니라 Label 로 둔다. 문자열이면 저장소 이름(`@rules_bun`)이
# 박혀서 모듈 이름이 바뀌거나 repo_name 이 다르게 매핑되면 깨진다.
BUN_TOOLCHAIN_TYPE = Label("//bun:toolchain_type")

BunInfo = _BunInfo
