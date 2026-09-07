<!-- Generated with Stardoc: http://skydoc.bazel.build -->

Bun 툴체인 룰.

툴체인 해석은 빌트인 `platform_common.ToolchainInfo` 만 인정한다.
동명의 커스텀 provider 를 선언하면 그것이 빌트인을 가려서
"does not provide ToolchainInfo" 로 해석이 실패한다.

<a id="bun_toolchain"></a>

## bun_toolchain

<pre>
load("@rules_bun//bun:toolchain.bzl", "bun_toolchain")

bun_toolchain(<a href="#bun_toolchain-name">name</a>, <a href="#bun_toolchain-bun">bun</a>, <a href="#bun_toolchain-version">version</a>)
</pre>

Bun 툴체인을 정의한다.

**ATTRIBUTES**


| Name  | Description | Type | Mandatory | Default |
| :------------- | :------------- | :------------- | :------------- | :------------- |
| <a id="bun_toolchain-name"></a>name |  A unique name for this target.   | <a href="https://bazel.build/concepts/labels#target-names">Name</a> | required |  |
| <a id="bun_toolchain-bun"></a>bun |  hermetic 하게 내려받은 Bun 실행 파일.   | <a href="https://bazel.build/concepts/labels">Label</a> | required |  |
| <a id="bun_toolchain-version"></a>version |  이 툴체인이 제공하는 Bun 버전.   | String | required |  |


