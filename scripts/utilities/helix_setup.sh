#!/usr/bin/env bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
msg_info() {
    echo -e "${YELLOW}[INFO] $1${NC}"
}

msg_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

msg_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

msg_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check OS
get_os() {
    case "$(uname -s)" in
    Darwin*) echo 'macos' ;;
    Linux*) echo 'linux' ;;
    *) msg_error "Unsupported operating system" ;;
    esac
}

# Install Helix editor
install_helix() {
    msg_info "Installing Helix editor..."
    OS=$(get_os)

    if [ "$OS" = "macos" ]; then
        if command_exists "hx"; then
            msg_success "Helix is already installed"
            return
        fi
        brew install helix || msg_error "Failed to install Helix"
    elif [ "$OS" = "linux" ]; then
        # First, uninstall any APT version
        uninstall_helix_apt

        sudo apt update || msg_error "Failed to update apt"
        sudo apt install build-essential gcc g++ -y || msg_error "Failed to install build tools"
        if command_exists "ghq"; then
            ghq get https://github.com/helix-editor/helix
            cd "$(ghq root)/github.com/helix-editor/helix"
        else
            git clone https://github.com/helix-editor/helix.git "$HOME/helix"
            cd "$HOME/helix"
        fi
        cargo install --path helix-term --locked || msg_error "Failed to install Helix"
    fi

    msg_success "Helix installed successfully"
}

# Uninstall Helix from APT
uninstall_helix_apt() {
    msg_info "Checking for APT installation of Helix..."
    if dpkg -l | grep -q "helix"; then
        msg_info "Removing APT version of Helix..."
        sudo apt-get remove helix -y || msg_error "Failed to remove Helix"
        sudo add-apt-repository --remove ppa:maveonair/helix-editor -y || msg_warning "Failed to remove Helix repository"
        sudo apt update || msg_warning "Failed to update apt"
        msg_success "APT version of Helix removed successfully"
    else
        msg_info "No APT installation of Helix found"
    fi
}

# Upgrade Helix from source
upgrade_helix_from_source() {
    msg_info "Upgrading Helix from source..."

    # First, uninstall APT version if it exists
    uninstall_helix_apt

    # Determine Helix source directory
    HELIX_DIR=""
    if command_exists "ghq"; then
        HELIX_DIR="$(ghq root)/github.com/helix-editor/helix"
    else
        HELIX_DIR="$HOME/helix"
    fi

    # Update source code
    if [ -d "$HELIX_DIR" ]; then
        cd "$HELIX_DIR"
        git pull || msg_error "Failed to update Helix source code"
    else
        if command_exists "ghq"; then
            ghq get https://github.com/helix-editor/helix
            cd "$(ghq root)/github.com/helix-editor/helix"
        else
            git clone https://github.com/helix-editor/helix.git "$HOME/helix"
            cd "$HOME/helix"
        fi
    fi

    # Build and install
    cargo install --path helix-term --locked --force || msg_error "Failed to upgrade Helix"

    msg_success "Helix upgraded successfully"
}

# Install npm packages
install_npm_packages() {
    msg_info "Installing npm packages..."

    NPM_PACKAGES=(
        "bun@1.0.28"
        "@ansible/ansible-language-server"
        "dockerfile-language-server-nodejs"
        "@microsoft/compose-language-service"
        "pyright"
        "yaml-language-server@next"
        "typescript"
        "typescript-language-server"
        "vscode-langservers-extracted@4.8"
        "prettier"
        "bash-language-server"
    )

    for package in "${NPM_PACKAGES[@]}"; do
        msg_info "Installing $package..."
        npm install -g "$package" || msg_error "Failed to install $package"
    done

    msg_success "All npm packages installed successfully"
}

# Install pip packages
install_pip_packages() {
    msg_info "Installing pip packages..."

    PIP_PACKAGES=(
        "pylyzer"
        "black"
        "yamllint"
        "beautysh"
    )

    for package in "${PIP_PACKAGES[@]}"; do
        msg_info "Installing $package..."
        pip install "$package" || msg_error "Failed to install $package"
    done

    msg_success "All pip packages installed successfully"
}

# Install Go packages
install_go_packages() {
    msg_info "Installing Go packages..."

    GO_PACKAGES=(
        "golang.org/x/tools/gopls@latest"
        "github.com/go-delve/delve/cmd/dlv@latest"
        "golang.org/x/tools/cmd/goimports@latest"
        "github.com/nametake/golangci-lint-langserver@latest"
        "github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
        "github.com/google/yamlfmt/cmd/yamlfmt@latest"
    )

    for package in "${GO_PACKAGES[@]}"; do
        msg_info "Installing $package..."
        go install "$package" || msg_error "Failed to install $package"
    done

    msg_success "All Go packages installed successfully"
}

# Install system-specific packages
install_system_packages() {
    OS=$(get_os)
    msg_info "Installing system-specific packages for $OS..."

    if [ "$OS" = "macos" ]; then
        BREW_PACKAGES=(
            "marksman"
            "hashicorp/tap/terraform-ls"
            "taplo"
        )

        for package in "${BREW_PACKAGES[@]}"; do
            msg_info "Installing $package..."
            brew install "$package" || msg_error "Failed to install $package"
        done
    elif [ "$OS" = "linux" ]; then
        # Install marksman
        msg_info "Installing marksman..."
        wget https://github.com/artempyanykh/marksman/releases/download/2024-12-18/marksman-linux-x64 -O marksman
        chmod +x marksman
        mv marksman ~/.local/bin/marksman

        # Install terraform-ls
        msg_info "Installing terraform-ls..."
        wget https://releases.hashicorp.com/terraform-ls/0.36.3/terraform-ls_0.36.3_linux_amd64.zip
        unzip terraform-ls_0.36.3_linux_amd64.zip
        mv terraform-ls ~/.local/bin/terraform-ls
        rm terraform-ls_0.36.3_linux_amd64.zip

        # Install taplo
        msg_info "Installing taplo..."
        cargo install taplo-cli --locked --features lsp
    fi

    msg_success "All system-specific packages installed successfully"
}

# Install helix-gpt
install_helix_gpt() {
    msg_info "Installing helix-gpt..."

    # Clone repository using ghq or git
    if command_exists "ghq"; then
        ghq get https://github.com/leona/helix-gpt.git
        cd "$(ghq root)/github.com/leona/helix-gpt"
    else
        git clone https://github.com:leona/helix-gpt.git "$HOME/helix-gpt"
        cd "$HOME/helix-gpt"
    fi

    # Build and install
    bun build:bin
    cp dist/helix-gpt ~/.local/bin/helix-gpt

    msg_success "helix-gpt installed successfully"
}

# Install Rust components
install_rust_components() {
    msg_info "Installing Rust components..."
    rustup component add rust-analyzer
    cargo install erg
    msg_success "Rust components installed successfully"

}

# Install Ruby components
install_ruby_components() {
    msg_info "Installing Ruby components..."
    gem install --user-install ruby-lsp
    msg_success "Ruby components installed successfully"
}

# Install all dependencies
install_dependencies() {
    msg_info "Installing all dependencies..."
    install_npm_packages
    install_pip_packages
    install_go_packages
    install_system_packages
    install_helix_gpt
    install_rust_components
    install_ruby_components
    msg_success "All dependencies installed successfully"
}

# Main function
main() {
    # Create ~/.local/bin if it doesn't exist
    mkdir -p ~/.local/bin

    # Parse command line arguments
    case "$1" in
    --helix-only)
        install_helix
        ;;
    --deps-only)
        install_dependencies
        ;;
    --upgrade-helix)
        upgrade_helix_from_source
        ;;
    --help)
        echo "Usage: $0 [--helix-only | --deps-only | --upgrade-helix | --help]"
        ;;
    *)
        install_helix
        install_dependencies
        ;;
    esac
}

# Run main function with all arguments
main "$@"
