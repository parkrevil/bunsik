"""`//bun/private:semver.bzl` 의 단위 테스트.

툴체인이 필요 없는 순수 로직이므로 룰셋 워크스페이스에서 바로 돈다.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//bun/private:semver.bzl", "max_version", "version_key")

def _ordering_test_impl(ctx):
    env = unittest.begin(ctx)

    # 문자열 정렬이 틀리는 대표 사례.
    asserts.equals(env, "1.10.0", max_version(["1.4.2", "1.10.0"]))
    asserts.equals(env, "1.10.0", max_version(["1.10.0", "1.4.2"]))
    asserts.equals(env, "2.0.0", max_version(["2.0.0", "1.99.99"]))
    asserts.equals(env, "1.4.10", max_version(["1.4.2", "1.4.10"]))

    # 자리수가 달라도 비교된다. 반환값은 원본 문자열 그대로다.
    asserts.equals(env, "1.4", max_version(["1.4", "1.3.9"]))
    asserts.equals(env, "1.4.2.1", max_version(["1.4.2", "1.4.2.1"]))

    # 단일 원소.
    asserts.equals(env, "1.4.2", max_version(["1.4.2"]))

    return unittest.end(env)

def _prerelease_test_impl(ctx):
    env = unittest.begin(ctx)

    # semver 규칙: 정식 릴리스가 prerelease 보다 높다.
    asserts.equals(env, "1.4.2", max_version(["1.4.2-canary.1", "1.4.2"]))
    asserts.equals(env, "1.4.2", max_version(["1.4.2", "1.4.2-canary.1"]))

    # prerelease 끼리는 문자열로 비교한다. 이전 구현은 동률이라 앞의 것을
    # 그대로 골랐다.
    asserts.equals(env, "1.4.2-canary.2", max_version(["1.4.2-canary.2", "1.4.2-canary.1"]))
    asserts.equals(env, "1.4.2-canary.2", max_version(["1.4.2-canary.1", "1.4.2-canary.2"]))

    # release 가 다르면 prerelease 여부보다 release 가 우선한다.
    asserts.equals(env, "1.5.0-canary.1", max_version(["1.4.2", "1.5.0-canary.1"]))

    return unittest.end(env)

def _key_shape_test_impl(ctx):
    env = unittest.begin(ctx)

    release, is_stable, prerelease = version_key("1.4.2")
    asserts.equals(env, [1, 4, 2, 0], release)
    asserts.equals(env, 1, is_stable)
    asserts.equals(env, "", prerelease)

    release, is_stable, prerelease = version_key("1.4.2-canary.7")
    asserts.equals(env, [1, 4, 2, 0], release)
    asserts.equals(env, 0, is_stable)
    asserts.equals(env, "canary.7", prerelease)

    return unittest.end(env)

ordering_test = unittest.make(_ordering_test_impl)
prerelease_test = unittest.make(_prerelease_test_impl)
key_shape_test = unittest.make(_key_shape_test_impl)

def semver_test_suite(name):
    """이 파일의 테스트를 모두 등록한다.

    Args:
        name: 테스트 스위트 이름.
    """
    unittest.suite(
        name,
        ordering_test,
        prerelease_test,
        key_shape_test,
    )
