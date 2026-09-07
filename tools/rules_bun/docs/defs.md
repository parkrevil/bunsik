<!-- Generated with Stardoc: http://skydoc.bazel.build -->

공개 API. 소비자는 이 파일만 load 한다.

`//bun/private/...` 는 내부 구현이며 외부에서 참조하지 않는다.

<a id="BunInfo"></a>

## BunInfo

<pre>
load("@rules_bun//bun:defs.bzl", "BunInfo")

BunInfo(<a href="#BunInfo-bun">bun</a>, <a href="#BunInfo-version">version</a>, <a href="#BunInfo-tool_files">tool_files</a>)
</pre>

Bun 실행 파일을 호출하는 방법.

**FIELDS**

| Name  | Description |
| :------------- | :------------- |
| <a id="BunInfo-bun"></a>bun |  Bun 실행 파일 File. 액션에서는 `executable`/`tools` 로 넘긴다.    |
| <a id="BunInfo-version"></a>version |  Bun 버전 문자열. 분석 단계에서 버전별 분기에 쓴다.    |
| <a id="BunInfo-tool_files"></a>tool_files |  runfiles 에 넣어야 하는 파일들.    |


