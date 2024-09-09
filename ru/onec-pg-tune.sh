#!/bin/bash

### ======== Settings ======== ###

# PostgreSQL version
pg_ver=16

# PostgreSQL directory
pg_dir=/var/lib/pgpro/1c-$pg_ver/data

# Location of the main .conf file
pg_conf_main=$pg_dir/postgresql.conf

# Directory for our conf. files
pg_conf_dir=$pg_dir/conf.d

# Path to the .conf file to which we will write our parameters
pg_conf_tune=$pg_conf_dir/00-onec-tune.conf

### ======== Settings ======== ###

### -------- Functions -------- ###

# Privilege escalation function
function elevate {
    if [ "$EUID" -ne 0 ]; then
        echo "This script must be run with superuser privileges. Trying to elevate privileges with sudo."
        exec sudo bash "$0" "$@"
        exit 1
    fi
}

# Function for logging (when called, it outputs a message to the console containing date, time and the text passed in the first argument)
function log {
    echo
    echo "$(date '+%Y-%m-%d %H:%M:%S') -> $1"
    echo
}

# Function for string commenting
function find_and_comment {
    target=$1
    pattern_to_match=$2
    sed -e "/${pattern_to_match}/ s/^#*/#/" -i $target
}

# Function performing arithmetic operations
function calculate {
    declare -n result=$1
    num1=$2
    operator=$3
    num2=$4
    result=$(echo "$num1 $operator $num2" | bc)
}

# Message before start
function message_before_start {
    # Print message to console
    clear
    echo
    echo "IP: $show_ip"
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo

    # Wait until the user presses enter
    read -p "Нажмите Enter, чтобы начать: "
}

# Message at the end
function message_at_the_end {
    # Print message to console
    clear
    echo
    echo "IP: $show_ip"
    echo
    echo "Скрипт: $script_name"
    echo
    echo "Лог: $logfile_path"
    echo
    echo "Параметры записаны в файл: $pg_conf_tune"
    echo
    echo "PostgreSQL:"
    echo
    systemctl --no-pager status postgrespro-1c-$pg_ver | grep Active
    echo
}

### -------- Functions -------- ###

### -------- Preparation -------- ###

# Define the directory where this script is located
script_dir="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Define the name of this script
script_name=$(basename "$0")

# Defining the directory name and script name if the script is launched via a symbolic link located in /usr/local/bin
if [[ "$script_dir" == *"/usr/local/bin"* ]]; then
    real_script_path=$(readlink ${0})
    script_dir="$( cd -- "$(dirname "$real_script_path")" >/dev/null 2>&1 ; pwd -P )"
    script_name=$(basename "$real_script_path")
fi

# Path to this script
script_path="${script_dir}/${script_name}"

# Path to log file
logfile_path="${script_dir}/${script_name%%.*}.log"

# For console output
echo_tab='     '
show_ip=$(hostname -I)

# Privilege escalation
elevate

# Start logging
exec > >(tee -a "$logfile_path") 2>&1

### -------- Preparation -------- ###

### -------- Script start  -------- ###

# Message to log
log "Script start"

# Print message to console
message_before_start

### -------- Script start  -------- ###

### -------- Creating files and directories -------- ###

# Create a directory for our .conf files
mkdir -p $pg_conf_dir

# Create temporary files in /tmp
temp_pg_conf_main=$(mktemp)
temp_pg_conf_tune=$(mktemp)

# Create a temporary copy of the main .conf file
cp $pg_conf_main $temp_pg_conf_main

### -------- Creating files and directories -------- ###

### -------- Calculations -------- ###

# Message to log
log "Calculations"

# Get the current amount of RAM in megabytes
ram_total=$(free -m | grep Mem: | awk '{print $2}')

# Get the current number of cores
cpu_cores_total=$(nproc --all)

# Calculate the recommended values and set the result in variables
calculate shared_buffers $ram_total / 4
calculate work_mem $ram_total / 32
calculate maintenance_work_mem $ram_total / 16
calculate max_worker_processes $cpu_cores_total / 1
calculate max_parallel_workers_per_gather $cpu_cores_total / 2
calculate max_parallel_workers $cpu_cores_total / 1
calculate max_parallel_maintenance_workers $cpu_cores_total / 2
calculate min_wal_size $ram_total / 10
calculate max_wal_size $min_wal_size \* 4
calculate effective_cache_size $ram_total - $shared_buffers
calculate autovacuum_max_workers $cpu_cores_total / 2

### -------- Calculations -------- ###

### -------- Config generation -------- ###

# Message to log
log "Config generation"

# Array with our parameters
pg_conf_options=(
    "max_connections = 1000"
    "shared_buffers = ${shared_buffers}MB"
    "temp_buffers = 256MB"
    "work_mem = ${work_mem}MB"
    "maintenance_work_mem = ${maintenance_work_mem}MB"
    "max_files_per_process = 1000"
    "bgwriter_delay = 20ms"
    "bgwriter_lru_maxpages = 400"
    "bgwriter_lru_multiplier = 4.0"
    "effective_io_concurrency = 1000"
    "max_worker_processes = $max_worker_processes"
    "max_parallel_workers_per_gather = $max_parallel_workers_per_gather"
    "max_parallel_workers = $max_parallel_workers"
    "max_parallel_maintenance_workers = $max_parallel_maintenance_workers"
    "fsync = on"
    "synchronous_commit = off"
    "wal_buffers = 16MB"
    "commit_delay = 1000"
    "commit_siblings = 5"
    "min_wal_size = ${min_wal_size}MB"
    "max_wal_size = ${max_wal_size}MB"
    "checkpoint_completion_target = 0.9"
    "seq_page_cost = 0.1"
    "random_page_cost = 0.1"
    "effective_cache_size = ${effective_cache_size}MB"
    "autovacuum = on"
    "autovacuum_max_workers = $autovacuum_max_workers"
    "autovacuum_naptime = 20s"
    "row_security = off"
    "max_locks_per_transaction = 256"
    "escape_string_warning = off"
    "standard_conforming_strings = off"
    "huge_pages = try"
    "default_statistics_target = 500"
)

# Let's comment out all lines in the main conf file that contain target parameters
for line in "${pg_conf_options[@]}"
do
    key="${line%%=*}"
    find_and_comment $temp_pg_conf_main $key
done

# Write parameters from the array
for line in "${pg_conf_options[@]}"
do
    echo "$line" >> $temp_pg_conf_tune
done

# Add the path to the conf.d directory to the main configuration file
echo >> $temp_pg_conf_main
echo "# Include configuration files from directory" >> $temp_pg_conf_main
echo "include_dir = '$pg_conf_dir'" >> $temp_pg_conf_main

### -------- Config generation -------- ###

### -------- Applying changes -------- ###

# Message to log
log "Applying changes"

# Back up the main .conf file
time=$(date +%G_%m_%d_%H_%M_%S)
cp $pg_conf_main $pg_conf_main.bk.$time

# Stop the service
systemctl stop postgrespro-1c-$pg_ver

# Write changes from temporary files to master files
rm $pg_conf_main
rm $pg_conf_tune
cp $temp_pg_conf_main $pg_conf_main
cp $temp_pg_conf_tune $pg_conf_tune

# Fixing permissions
chown postgres:postgres $pg_conf_main
chown postgres:postgres $pg_conf_dir -R
chmod 700 $pg_conf_dir

# Start the service
systemctl start postgrespro-1c-$pg_ver

# Delete temporary files
rm $temp_pg_conf_main
rm $temp_pg_conf_tune

### -------- Applying changes -------- ###

### -------- Script end -------- ###

# Message to log
log "Script end"

# Print message to console
message_at_the_end

### -------- Script end -------- ###

