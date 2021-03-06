#!/bin/bash -l

set -o errexit
set -o nounset
set -o pipefail

tag=$(cat blob/tag)
GITHUB_ORG=${GITHUB_ORG:-cloudfoundry}
git clone "https://github.com/$GITHUB_ORG/$LANGUAGE-buildpack.git" source

pushd source
  export GOPATH="$PWD"
  export GOBIN=$PWD/.bin
  export PATH=$GOBIN:$PATH

  git checkout "$tag"
  git submodule update --init --recursive

  (cd "src/$LANGUAGE/vendor/github.com/cloudfoundry/libbuildpack/packager/buildpack-packager" && go install)

  buildpack-packager build --cached
popd

# shellcheck disable=SC2035
mv source/*_buildpack-cached*.zip buildpack-zip/
