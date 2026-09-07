"""공개 API. 소비자는 이 파일만 load 한다.

`//bun/private/...` 는 내부 구현이며 외부에서 참조하지 않는다.
"""

load("//bun/private:providers.bzl", _BunInfo = "BunInfo")

# 룰 작성자가 `toolchains` 속성에 넣는 툴체인 타입.
BUN_TOOLCHAIN_TYPE = "@rules_bun//bun/toolchain:type"

BunInfo = _BunInfo
