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
            "-c") colorize=true ;;
            "-f") fixme=true ;;
            "-s") summary=true ;;
            *) break ;;
        esac
        shift
    done

    re="(TODO$(truthy $fixme && echo '|FIXME')):"
    color="--color=$(truthy $colorize && echo 'always' || echo 'never')"
    if truthy $summary; then
        git grep -ncE $@ '(TODO|FIXME):'
    else
        # TODO: Setting color=always breaks alignment for some reason
        git grep -nE "$color" $@ "$re" | \
            sed 's/\([^:]*:[^:]*\):[ \t]*\(.*\)/\1\t\2/'
    fi
}

whoami() {
    echo "$(git config user.name) ($(git config user.email))"
}

www() {
    branch="$(git rev-parse --abbrev-ref HEAD)"
    defaultBranch="$(git config init.defaultBranch)"
    remote="$(git config branch."$branch".remote || git config branch."$defaultBranch".remote || git config branch.main.remote || git config branch.master.remote)"
    if [ -z "$remote" ]; then
        echo "ERROR: Couldn't guess what host to use: current branch doesn't have a remote and default ($defaultBranch) doesn't either" > /dev/stderr
        exit 1
    fi
    url="$(git remote get-url "$remote")"
    http="$(echo "$url" | sed 's/git@\([^:]*\):\(.*\)/https:\/\/\1\/\2/')"

    # format git@host:repo/path
    if [ "$1" = '-p' ]; then
        echo "$http"
    else
        x-www-browser "$http"
    fi
}

$@