#!/bin/bash

# Link to installable script
target_script_url=https://raw.githubusercontent.com/larionit/onec-pg-tune/main/onec-pg-tune.sh

# Link to this installation script (needed in case of privilege escalation via sudo)
setup_script_url=https://raw.githubusercontent.com/larionit/onec-pg-tune/main/setup.sh

# Temporary file for this installation script (needed in case of sudo privilege escalation)
temp_setup_script=$(mktemp)

# Loading this installation script (needed in case of sudo privilege escalation)
curl -fsSL "$setup_script_url" -o "$temp_setup_script"

# Increase privileges
if [[ "$EUID" -ne 0 ]]; then
    exec sudo bash "$temp_setup_script" "$@"
fi

# Specify a name for the directory to be created (we take the name of the script to be installed without extension)
target_script_name=$(basename "$target_script_url")
target_script_dir_name="${target_script_name%.*}"
target_script_dir="/opt/${target_script_dir_name}"
target_script_path="$target_script_dir/$target_script_name"

# Rename the file if it already exists, if not, create a directory.
if [ -f "$target_script_path" ]; then
    time=$(date +%G_%m_%d_%H_%M_%S)
    cp "$target_script_path" "$target_script_path.old.$time"
else
    mkdir $target_script_dir
fi

# Download the script to be installed
curl -fsSL "$target_script_url" -o "$target_script_path"

# Grant execute permission
chmod +x "$target_script_path"

# Specify the path for the symbolic link
target_script_symlink="/usr/local/bin/${target_script_name%.*}"

# Create a symbolic link
if [ ! -L "$target_script_symlink" ]; then
    ln -s "$target_script_path" "$target_script_symlink"
fi

# Run the script to be installed
bash "$target_script_path"

# Deleting a temporary installation script file
rm -f "$temp_setup_script"