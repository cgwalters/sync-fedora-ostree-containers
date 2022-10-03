#!/bin/bash

set -euo pipefail

ostreeref=$1
shift
image=$1
shift

runv () {
    ( set -x ; $@ )
}

cd $(mktemp -d -p /var/tmp)
runv skopeo inspect -n docker://${image} > inspect.json || true
container_commit=
if test -s inspect.json; then
    container_commit=$(jq -r '.Labels["ostree.commit"]')
fi

mkdir repo
ostree --repo=repo init --mode=bare-user
cat /etc/ostree/remotes.d/fedora.conf >> repo/config
runv ostree --repo=repo pull --commit-metadata-only fedora:$ostreeref
current_commit=$(ostree --repo=repo rev-parse fedora:$ostreeref)

if test "$current_commit" == "$container_commit"; then
    echo "Generated container image is up to date at commit $current_commit"
    exit 0
fi

runv ostree --repo=repo pull fedora:$ostreeref
runv rpm-ostree compose container-encapsulate --format-version 1 \
    --repo repo $current_commit oci:tmp
# Retry since github actions networking flakes sometimes
# TODO: add retries into skopeo, docker seems to do it
for n in {0..2} max; do
    if runv skopeo copy oci:tmp docker://$image; then
        break
    else
        if test $n == max; then
            exit 1
        fi
    fi
done
