#!/usr/bin/env bash

source "$(dirname "$BASH_SOURCE")/../../init/init.sh"

# Function to install pyenv and Python dependencies for Linux
install_pyenv_linux() {
    echo_with_color "$GREEN" "Installing pyenv and Python dependencies for Linux..."
    sudo yum update -y || exit_with_error "Failed to update yum package list"
    sudo yum install gcc make patch zlib-devel bzip2 bzip2-devel \
                    readline-devel sqlite sqlite-devel openssl-devel \
                    tk-devel libffi-devel xz-devel -y

    if curl https://pyenv.run | bash; then
        echo_with_color "$GREEN" "pyenv installed successfully."
    else
        exit_with_error "Failed to install pyenv."
    fi
}

# Function to install and set up Python version using pyenv
setup_python_version() {
    if pyenv install -s "${PYTHON_VERSION}"; then
        echo_with_color "$GREEN_COLOR" "Python ${PYTHON_VERSION} installed successfully."
    else
        exit_with_error "Failed to install Python ${PYTHON_VERSION}, please check pyenv setup."
    fi

    if pyenv global "${PYTHON_VERSION}"; then
        echo_with_color "$GREEN_COLOR" "Python ${PYTHON_VERSION} is now in use."
    else
        exit_with_error "Failed to set Python ${PYTHON_VERSION} as global, please check pyenv setup."
    fi
}

initialize_pyenv() {
    # Initialize pyenv for the current session
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
}

update_bashrc() {
    local bashrc_file="$HOME/.bashrc"
    echo_with_color "$GREEN" "Updating $bashrc_file..."
    echo "" >> "$bashrc_file"
    add_line_to_file "export PYENV_ROOT=\"\$HOME/.pyenv\"" "$bashrc_file"
    add_line_to_file "[[ -d \$PYENV_ROOT/bin ]] && export PATH=\"\$PYENV_ROOT/bin:\$PATH\"" "$bashrc_file"
    add_line_to_file "eval \"\$(pyenv init -)\"" "$bashrc_file"
    add_line_to_file "eval \"\$(pyenv virtualenv-init -)\"" "$bashrc_file"
}

# Main installation process
if [ -z "${PYTHON_VERSION:-}" ]; then
    exit_with_error "PYTHON_VERSION is not set. Please specify the Python version to install."
fi

if ! command_exists curl; then
    exit_with_error "The curl command is required to install pyenv but it's not installed."
fi

if [ ! -f "$HOME/.pyenv/bin/pyenv" ]; then
    echo_with_color "$YELLOW" "pyenv is not installed. Installing pyenv and Python dependencies..."
    install_pyenv_linux
    initialize_pyenv
    setup_python_version
    update_bashrc
else
    echo_with_color "$GREEN" "pyenv is already installed and appears to be properly set up."
    initialize_pyenv
    setup_python_version
fi