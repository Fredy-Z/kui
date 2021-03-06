#!/usr/bin/env bash

#
# Copyright 2019 IBM Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

shopt -s extglob
set -e
set -o pipefail

target=npm-packs
mkdir -p "$target"
rm -rf "$target"/*.tgz
target=$(cd "$target" && pwd)

rm -rf node_modules

cp package.json bak.json

# create npm packs
for pkg in ../../packages/{app,kui-builder,proxy,tests} ../../plugins/*; do
    # check for inclusion constraints; e.g. package.json -> .kui.headless == false
    if [ -n "$1" ]; then
        OK=$(cat $pkg/package.json | jq --raw-output .kui.$1)
        if [ "$OK" == "false" ] || [ "$(printenv $OK)" == "false" ]; then
            # skip!
            echo "skipping $(basename $pkg)"
            continue
        fi
    fi

    echo "adding $(basename $pkg)"
    (cd $pkg && pack=$(npm -s pack) && mv $pack "$target") &
done
wait

# npm install those npm packs
npm install --save --no-package-lock "$target"/!(*builder*)
npm install --save-dev --no-package-lock "$target"/*builder*

#
# make absolute path refs to the npm packs we just created (in the for pkg loop above)
#
PJSON=$(node -e 'const pjson = require("./package.json"); function abs(deps) { for (let key in deps) { const abs = require("path").resolve(deps[key].substring(5)); deps[key] = `file:${abs}`; } } abs(pjson.dependencies); abs(pjson.devDependencies); console.log(JSON.stringify(pjson, undefined, 2))')
echo "$PJSON" > package.json

for i in node_modules/@kui-shell/plugin-*; do
    for j in $(cat "$i"/package.json | jq -c .kui.exclude.$1 | sed -e 's/\[//' -e 's/\]//' -e 's/"//g' -e 's/,/ /g'); do
        if [[ $j != "null" ]]; then
            echo "Uninstalling $j from `basename $i`"
            (cd "$i" && npm uninstall --save "$j")
        fi
    done
done
npm prune
