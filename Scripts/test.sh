#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ "$(xcode-select -p)" == '/Library/Developer/CommandLineTools' ]]; then
    framework_path='/Library/Developer/CommandLineTools/Library/Developer/Frameworks'
    swift test --disable-xctest --enable-swift-testing -Xswiftc -F -Xswiftc "$framework_path" -Xlinker -F -Xlinker "$framework_path" -Xlinker -rpath -Xlinker "$framework_path" -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib "$@"
else
    swift test --disable-xctest --enable-swift-testing "$@"
fi
