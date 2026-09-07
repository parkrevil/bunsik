"""Bun 릴리스 무결성 해시.

출처: 각 릴리스의 공식 `SHASUMS256.txt`
  https://github.com/oven-sh/bun/releases/download/bun-v<version>/SHASUMS256.txt

integrity 값은 다음으로 만든다.
  grep '  bun-<platform>.zip$' SHASUMS256.txt | awk '{print $1}' \
    | xxd -r -p | base64 -w0 | sed 's/^/sha256-/'
"""

TOOL_VERSIONS = {
    "1.4.2": {
        "linux-x64": "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=",
        "linux-aarch64": "sha256-VDKLvC2cjgyfiSxUTWbFeoO4QTnjSQnl7oF1jxrI/ac=",
        "darwin-x64": "sha256-gFINfhdSYwjJGF0mFnmsbSd5jTgDoOn3/5Ehq4r/sBI=",
        "darwin-aarch64": "sha256-kJh6OhbX21VtiGrD1VHnttPt8KHPQ6yu1iLoZ2vh0S8=",
        "windows-x64": "sha256-zkwXSXsvKXEqmdPVPwKN4ozULjusuFiVmefwAOSbZAU=",
    },
}
