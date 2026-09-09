"""버전 비교.

문자열 정렬은 쓸 수 없다 — `"1.10.0" < "1.4.2"` 가 되기 때문이다.
Starlark 에는 `sorted(key=...)` 가 없어 비교를 직접 구현한다.

정확한 semver 구현이 목표가 아니다. Bun 이 실제로 내는 버전 문자열
(`1.4.2`, `1.4.2-canary.20260101`)을 올바른 순서로 세우는 것이 목표다.
지원 범위 밖의 입력은 조용히 삼키지 않고 `fail()` 한다.
"""

_MAX_SEGMENTS = 4

def _parse_number(text, version):
    """숫자만으로 이뤄진 문자열을 int 로 바꾼다. 아니면 실패한다."""
    if not text:
        fail("버전 \"{}\" 의 세그먼트가 비어 있다.".format(version))
    for ch in text.elems():
        if not ch.isdigit():
            fail(
                "버전 \"{}\" 에 숫자가 아닌 세그먼트 \"{}\" 가 있다. ".format(version, text) +
                "지원 형식은 `<숫자>(.<숫자>)*` 이며 뒤에 `-<prerelease>` 를 붙일 수 있다.",
            )
    return int(text)

def version_key(version):
    """비교 가능한 키를 만든다.

    Args:
        version: `1.4.2` 또는 `1.4.2-canary.20260101` 형태의 문자열.

    Returns:
        `(release, is_stable, prerelease)` 튜플.
        `release` 는 정수 리스트(자리수를 4로 맞춘다).
        `is_stable` 은 prerelease 가 없으면 1, 있으면 0 —
        semver 규칙대로 `1.4.2` 가 `1.4.2-canary` 보다 크다.
        `prerelease` 는 동률일 때만 쓰는 문자열이다.
    """
    if not version:
        fail("버전 문자열이 비어 있다.")

    parts = version.split("-", 1)
    core = parts[0]
    prerelease = parts[1] if len(parts) > 1 else ""

    segments = core.split(".")
    if len(segments) > _MAX_SEGMENTS:
        fail(
            "버전 \"{}\" 의 세그먼트가 {} 개다. 최대 {} 개까지 지원한다.".format(
                version,
                len(segments),
                _MAX_SEGMENTS,
            ),
        )

    release = [_parse_number(s, version) for s in segments]
    for _ in range(_MAX_SEGMENTS - len(release)):
        release.append(0)

    return (release, 0 if prerelease else 1, prerelease)

def max_version(versions):
    """가장 높은 버전을 고른다.

    Args:
        versions: 버전 문자열 리스트. 비어 있으면 실패한다.

    Returns:
        가장 높은 버전 문자열.
    """
    if not versions:
        fail("버전 목록이 비어 있다.")

    best = versions[0]
    best_key = version_key(best)
    for candidate in versions[1:]:
        key = version_key(candidate)
        if key > best_key:
            best, best_key = candidate, key
    return best
