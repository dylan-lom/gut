#!/usr/bin/env sh
#
# gut: git but gross
# author: Dylan Lom <djl@dylanlom.com>

VERSION=0.0.2

# interals / "guts"
version() { echo "$VERSION"; }
thisBranch() { git rev-parse --abbrev-ref HEAD; }
thisRemote() { git config branch."$(thisBranch)".remote; }
defaultBranch() { git config init.defaultBranch; }
defaultRemote() { git config branch."$(defaultBranch)".remote; }
guessRemote() {
    thisRemote || defaultRemote || git config branch.main.remote || git config branch.master.remote
}

install() {
    dest=""
    if [ ! -z "$1" ]; then
        dest="$1"
    else
        msg="Where do you want to install to?
    1: ~/bin (default)
    2: /usr/local/bin
    3: ~/.local/bin
    4: CANCEL
"
        confirm "$msg" 1 2 3 4
        case "$?" in
            0) dest="$HOME/bin/gut" ;;
            1) dest="/usr/local/bin/gut" ;;
            2) dest="$HOME/.local/bin/gut" ;;
            3) return ;;
        esac
    fi

    cp "$argv0" "$dest"
}

# TODO: Actually follow the spec & all transports as per git-clone(1)
repoToPath() {
    repo="$1"
    if (echo "$repo" | grep -q 'ssh:\/\/'); then
        host="$(echo "$repo" | sed 's/ssh:\/\/[a-zA-Z]*@\([^:]*\):.*/\1/')"
        path="$(echo "$repo" | sed 's/ssh:\/\/[^:]*:\(.*\)/\1/' | sed 's/^\///' | sed s'/\.git$//')"
    elif (echo "$repo" | grep -q 'https\?:\/\/'); then
        host="$(echo "$repo" | sed 's/https\?:\/\/\([^/]*\)\/.*/\1/')"
        path="$(echo "$repo" | sed 's/https\?:\/\/[^/]*\/\(.*\)/\1/')"
    elif (echo "$repo" | grep -q 'git:\/\/'); then
        host="$(echo "$repo" | sed 's/git:\/\/\([^/:]*\).*/\1/')"
        path="$(echo "$repo" | sed 's/git:\/\/[^/:]*[^/]*\/\(.*\)/\1/')"
    else
        echo "ERROR: Unrecognised transport to repo $repo" > /dev/stderr
        exit 1
    fi

    echo "$host/$path"
}

# TODO: Review commands
# COMMANDS
gut_commands=" add amend checkout clone commit git guts log push root stash status todo whoami www "

# Expose internal functions (the guts).
# Also to expose the install command a level deeper because I felt gross having
# it as a top-level command.
guts() {
    $@
}

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
    test "$#" -gt 0 && git add $@
    git status --porcelain | grep -q '^[^ ]' \
        && git commit --amend \
        || git commit --amend -a
}

checkout() {
    truthy "$1" && target="$1" || target="$(git config init.defaultBranch)"
    git checkout "$target"
}

# Clone repo into $host/$path/$to/$repo, taking into account PWD
# eg. clone git@github.com:dylan-lom/gut.git => ./github.com/dylan-lom/gut
#     if $PWD=~/src/github.com               => ./dylan-lom/gut
clone() {
    if [ -z "$1" ]; then
        echo 'ERROR: Please provide repo to clone...' > /dev/stderr
        exit 1
    fi

    repo="$1"
    path="$(repoToPath "$repo")"
    dest="" # where we need to clone to
    while (echo "$PWD" | grep -qv "$path\$"); do

        # Handle the case where none of $path occurs in PWD and we exhaust
        # all '/' characters in $path
        # FIXME: I feel like this doesn't need to be its own case...
        if (echo "$path" | grep -qv '/'); then
            dest="$path/$dest"
            path=""
            break
        fi

        dest="$(echo $path | rev | cut -d '/' -f1 | rev)/$dest"
        path="$(echo $path | rev | cut -d '/' -f2- | rev)"

    done

    git clone "$repo" "$dest"
}


# 1. If filenames provided as arguments, stages those files and commit
# 2. If anything is already staged, commit that (regular git behavior)
# 3. If there are unstaged changes, commit those
# 4. If there are no unstaged changes, but are untracked files interactively add
commit() {
    if [ "$#" -gt 0 ]; then
        git add $@
    elif git status --porcelain | grep -q '^[AMDRC]'; then
        true # nothing to do, everything is already staged
    elif git status --porcelain | grep -q '^.[MDRC]'; then
        git add -u # add tracked files
    else
        add
    fi

    git commit
}


log() {
    git log --pretty=oneline --abbrev-commit
}

# 1. If any arguments given, use those
# 2. If branch already has a remote, push to that
# 3. Try to guess remote and push to that
push() {
    if [ ! -z "$1" ]; then
        git push $@
    elif thisRemote > /dev/null 2>&1; then
        git push
    else
        confirm "No upstream; use $(guessRemote)?" \
            && git push -u "$(guessRemote)" "$(thisBranch)" \
            || echo "ABORT: Push cancelled; no remote" >/dev/stderr
    fi
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
    comparisonBranch="$(defaultBranch)"
    # Current branch has remote
    thisRemote > /dev/null && comparisonBranch="$(thisRemote)/$(thisBranch)"
    aheadCount="$(git rev-list "$comparisonBranch.." --count)"
    behindCount="$(git rev-list "..$comparisonBranch" --count)"
    test "$aheadCount" -gt 0 && echo "Ahead of $comparisonBranch by $aheadCount commits"
    test "$behindCount" -gt 0 && echo "Behind $comparisonBranch by $behindCount commits"

    git status --short
}

todo() {
    # FIXME: Use getopts
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
        git grep -ncE $@ "$re"
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
    remote="$(guessRemote)"
    if [ -z "$remote" ]; then
        echo "ERROR: Couldn't guess what remote to use..." > /dev/stderr
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

argv0="$0"

if echo "$gut_commands" | grep -qv " $1 "; then
    echo "ERROR: Unknown command \`"$1"\`" > /dev/stderr
    exit 1
fi

$@
