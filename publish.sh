#!/usr/bin/env bash
set -euo pipefail

app=$1

rm -rf ./www/pkg
./build.sh --release $app

hash=$(b3sum ./www/pkg/* | b3sum - --no-names)
echo "Hash is: ${hash}"
sed -i -E "s/pkg-[^/]+/pkg-$hash/g" ~/dev/bosthlm/app/views/listings/index.html.erb
rm -rf ~/dev/bosthlm/public/roc/pkg-*
cp -r ./www/pkg/ ~/dev/bosthlm/public/roc/pkg-$hash/
