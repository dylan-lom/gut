#!/usr/bin/env sh
#
# gut: git but gross
# author: Dylan Lom <djl@dylanlom.com>

add() {
    truthy "$1" \
        && git add $1 \
        || (for f in $(git status --porcelain | cut -c4-); do \
            confirm "Add $f?" && git add "$(root)/$f"; done)
}

# If anything already added (staged):
#    then amend that
#    else amend all
amend() {
    git status --porcelain | grep -q '^[^ ]*A' \
        && git commit --amend \
        || git commit --amend -a
}

alias co='checkout'
checkout() {
    truthy "$1" && target="$1" || target="$(git config init.defaultBranch)"
    git checkout "$target"
}


# If anything already added (staged):
#    then commit that
#    else prompt user to stage then commit
commit() {
    git status --porcelain | grep -q '^[^ ]*A' \
        && git commit \
        || (status; add; git commit)
}

root() {
    git rev-parse --show-toplevel
}

alias save='stash'
stash() {
    truthy "$1" \
        && git stash push -m "$1" \
        || git stash push
}

status() {
    git status --short
}

todo() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            "-d") detail=true ;;
            "-c") colorize=true ;;
            "-f") fixme=true ;;
            *) break ;;
        esac
        shift
    done

    re="(TODO$(truthy $fixme && echo '|FIXME')):"
    color="--color=$(truthy $colorize && echo 'always' || echo 'never')"
    if truthy $detail; then
        # TODO: Setting color=always breaks alignment for some reason
        git grep -nE "$color" $@ "$re" | \
            sed 's/\([^:]*:[^:]*\):[ \t]*\(.*\)/\1\t\2/'
    else
        git grep -ncE $@ '(TODO|FIXME):'
    fi
}

whoami() {
    echo "$(git config user.name) ($(git config user.email))"
}

$@
