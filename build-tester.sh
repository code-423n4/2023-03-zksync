#!/usr/bin/env bash

cd era-compiler-tester

if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install cmake ninja coreutils parallel
	ln -s solc-macos ../solc
elif [[ -f '/etc/arch-release' ]]; then
        sudo pacman -S cmake ninja clang lld parallel1
	ln -s solc-linux ../solc
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt install cmake ninja-build clang-13 lld-13 parallel pkg-config clang lld libstdc++-12-dev
	ln -s solc-linux ../solc
else
        echo "Unsupported OS"
        exit 1
fi

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"
# You may need to restart the shell after the above to have your rust properly registered
cargo install compiler-llvm-builder
zkevm-llvm clone && zkevm-llvm build
cargo build --release
