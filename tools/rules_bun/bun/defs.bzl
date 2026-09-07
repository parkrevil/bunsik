"""공개 API 재export. 사용자는 이 파일만 load 한다."""

load("//bun:toolchain.bzl", _BunInfo = "BunInfo")

BunInfo = _BunInfo
