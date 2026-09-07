"""Bun 이 배포하는 플랫폼과 Bazel 제약조건의 매핑.

키는 Bun 릴리스 자산 이름의 접미사와 정확히 일치해야 한다
(`bun-<key>.zip`, 압축 해제 시 `bun-<key>/` 디렉터리).
"""

PLATFORMS = {
    "linux-x64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:x86_64",
        ],
    ),
    "linux-aarch64": struct(
        compatible_with = [
            "@platforms//os:linux",
            "@platforms//cpu:aarch64",
        ],
    ),
    "darwin-x64": struct(
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:x86_64",
        ],
    ),
    "darwin-aarch64": struct(
        compatible_with = [
            "@platforms//os:macos",
            "@platforms//cpu:aarch64",
        ],
    ),
    "windows-x64": struct(
        compatible_with = [
            "@platforms//os:windows",
            "@platforms//cpu:x86_64",
        ],
    ),
}
