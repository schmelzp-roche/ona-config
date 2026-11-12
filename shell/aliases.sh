# Shell aliases. Sourced from shell/env.sh (bash and zsh).

# git
alias gst='git status'
alias githist='git log --oneline'
alias githisttags='git log --oneline --tags'
alias gp='git push origin'
alias gitclean='git clean -xfd'

# cargo
alias cgr='cargo run'
alias cgb='cargo build'
alias cgbr='cargo build --release'
alias cgt='cargo nextest run'
alias cgl='cargo clippy --all-targets --all-features -- -D warnings'
alias cgf='cargo fmt'
alias cgc='cargo llvm-cov nextest --show-missing-lines'

# navigation
alias ..="cd .."
alias ...="cd ../.."
alias uu="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
