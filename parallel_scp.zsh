#!/usr/bin/env zsh

# Parallel SCP Function
# File: ~/.config/zsh/functions/parallel_scp.zsh
# Usage: Source this file in your ~/.zshrc
# Example: source ~/.config/zsh/functions/parallel_scp.zsh

# Parallel SCP function - Fully compatible with SCP
parallel_scp() {
    local USAGE="
Usage: parallel_scp [SCP_OPTIONS] [PARALLEL_OPTIONS] <source> <destination>

SCP OPTIONS (fully compatible with scp):
    -1                  Use SSH protocol version 1
    -2                  Use SSH protocol version 2
    -3                  Copy between two remote hosts via local host
    -4                  Use IPv4 addresses only
    -6                  Use IPv6 addresses only
    -B                  Batch mode (don't ask for passwords)
    -C                  Enable compression
    -c cipher           Select encryption cipher
    -F ssh_config       Specify SSH config file
    -i identity_file    SSH private key file
    -l limit            Limit bandwidth in Kbit/s
    -o ssh_option       Pass SSH option (e.g., -o Port=2222)
    -P port             Port number (capital P)
    -p                  Preserve file times and modes
    -q                  Quiet mode
    -r                  Recursive (for directories)
    -S program          Specify SSH program
    -v                  Verbose output

PARALLEL OPTIONS:
    -h, --hosts FILE    File containing IP addresses (required)
    -u, --user USER     SSH username (default: $USER)
    -t, --timeout SEC   Connection timeout (default: 30)
    --max-parallel N    Maximum parallel processes (default: 10)
    --password PASS     SSH password (NOT SECURE - use keys instead)
    --ask-pass          Prompt for password for each host
    --retry N           Retry failed transfers (default: 0)
    --dry-run           Show what would be done, don't execute
    --debug             Show debug information
    --help             Show this help message

EXAMPLES:
    # Basic usage
    parallel_scp -h hosts.txt -u alba -P 9191 -r bundle /opis/app/
    
    # With compression
    parallel_scp -h servers.txt -u root -C -r mydir/ /backup/
    
    # SSH key with batch mode
    parallel_scp -h hosts.txt -u alba -i ~/.ssh/id_rsa -B -r src/ /dest/
    
    # With password (not secure)
    parallel_scp -h hosts.txt -u alba --password 'mypass' -r app/ /opt/
    
    # Bandwidth limiting
    parallel_scp -h hosts.txt -u alba -l 1024 -C largefile.tar.gz /tmp/
    
    # SSH options
    parallel_scp -h hosts.txt -u alba -o Port=9191 -o StrictHostKeyChecking=no file.txt /tmp/
    
    # Preserve file permissions
    parallel_scp -h hosts.txt -u alba -p -r webapp/ /var/www/
    
    # Retry failed transfers
    parallel_scp -h hosts.txt -u alba --retry 2 -r app/ /opt/
    
    # Dry run (show only)
    parallel_scp -h hosts.txt -u alba --dry-run -r app/ /opt/
"

    local scp_options=()
    local hosts_file=""
    local user="$USER"
    local timeout="30"
    local max_parallel="10"
    local password=""
    local ask_pass=false
    local retry_count="0"
    local dry_run=false
    local debug_mode=false
    local source_path=""
    local dest_path=""
    local args_ended=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            # Parallel-specific options
            -h|--hosts)
                hosts_file="$2"
                shift 2
                ;;
            -u|--user)
                user="$2"
                shift 2
                ;;
            -t|--timeout)
                timeout="$2"
                shift 2
                ;;
            --max-parallel)
                max_parallel="$2"
                shift 2
                ;;
            --password)
                password="$2"
                shift 2
                ;;
            --ask-pass)
                ask_pass=true
                shift
                ;;
            --retry)
                retry_count="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --debug)
                debug_mode=true
                shift
                ;;
            --help)
                echo "$USAGE"
                return 0
                ;;
            -[123456BCpqrv])
                scp_options+=("$1")
                shift
                ;;
            -[cFiloPS])
                scp_options+=("$1" "$2")
                shift 2
                ;;
            -o)
                scp_options+=("-o" "$2")
                shift 2
                ;;
            -*)
                echo "Unknown or unsupported option: $1"
                echo "Use --help for supported SCP options"
                return 1
                ;;
            *)
                if [[ -z "$source_path" ]]; then
                    source_path="$1"
                elif [[ -z "$dest_path" ]]; then
                    dest_path="$1"
                else
                    echo "Too many parameters: $1"
                    echo "$USAGE"
                    return 1
                fi
                shift
                ;;
        esac
    done

    # Check required parameters
    if [[ -z "$hosts_file" ]]; then
        echo "Error: Hosts file not specified (-h/--hosts)"
        echo "$USAGE"
        return 1
    fi

    if [[ -z "$source_path" ]] || [[ -z "$dest_path" ]]; then
        echo "Error: Source and destination paths not specified"
        echo "$USAGE"
        return 1
    fi

    # Check hosts file existence
    if [[ ! -f "$hosts_file" ]]; then
        echo "Error: Hosts file not found: $hosts_file"
        return 1
    fi

    # Check source file/directory existence
    if [[ ! -e "$source_path" ]]; then
        echo "Error: Source file/directory not found: $source_path"
        return 1
    fi

    # Max parallel validation
    if ! [[ "$max_parallel" =~ ^[0-9]+$ ]] || [[ "$max_parallel" -lt 1 ]]; then
        echo "Error: Max parallel value must be a positive number"
        return 1
    fi

    # Retry count validation
    if ! [[ "$retry_count" =~ ^[0-9]+$ ]]; then
        echo "Error: Retry count must be a positive number"
        return 1
    fi

    # Password validation
    if [[ "$ask_pass" == true ]] && [[ -n "$password" ]]; then
        echo "Error: --ask-pass and --password cannot be used together"
        return 1
    fi

    if [[ "$ask_pass" == true ]]; then
        echo -n "SSH password: "
        read -s password
        echo ""
    fi

    # Build SCP command - add timeout
    local scp_cmd="scp"
    local has_timeout_option=false
    local has_connect_timeout=false
    
    # Check existing SSH options
    for ((i=1; i<=${#scp_options[@]}; i++)); do
        if [[ "${scp_options[i]}" == "-o" ]] && [[ "${scp_options[i+1]}" == *"ConnectTimeout"* ]]; then
            has_connect_timeout=true
            break
        fi
    done
    
    # Add ConnectTimeout if not present
    if [[ "$has_connect_timeout" == false ]]; then
        scp_options+=("-o" "ConnectTimeout=$timeout")
    fi

    # Read hosts file and filter empty lines
    local hosts=($(grep -v '^[[:space:]]*$' "$hosts_file" | grep -v '^#' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'))
    
    if [[ ${#hosts[@]} -eq 0 ]]; then
        echo "Error: No valid IP addresses found in hosts file"
        return 1
    fi

    # Dry run check
    if [[ "$dry_run" == true ]]; then
        echo "🔍 DRY RUN - Showing only, no operations will be performed"
        echo ""
        echo "📋 Hosts to process (${#hosts[@]} total):"
        for host in "${hosts[@]}"; do
            echo "   $host"
        done
        echo ""
        echo "🚀 Command to execute:"
        echo "   $scp_cmd ${scp_options[*]} \"$source_path\" \"$user@HOST:$dest_path\""
        echo ""
        echo "⚙️  Settings:"
        echo "   User: $user"
        echo "   Timeout: ${timeout}s"
        echo "   Max Parallel: $max_parallel"
        echo "   Retry: $retry_count"
        echo "   SCP Options: ${scp_options[*]}"
        return 0
    fi

    echo "🚀 Starting Parallel SCP..."
    echo "📁 Source: $source_path"
    echo "📍 Destination: $dest_path"
    echo "👤 User: $user"
    echo "⏱️  Timeout: ${timeout}s"
    echo "🔧 SCP Options: ${scp_options[*]}"
    echo "🔄 Max Parallel: $max_parallel"
    echo "🔄 Retry Count: $retry_count"
    echo "📋 Hosts: ${#hosts[@]} servers"
    echo ""

    # Job management for parallel processing
    local success_count=0
    local fail_count=0
    local running_jobs=0
    local completed_hosts=()
    local failed_hosts=()
    local active_pids=()
    local all_hosts=("${hosts[@]}")  # Store all hosts
    declare -A pid_to_host
    declare -A host_retry_count

    # Reset retry count for each host
    for host in "${hosts[@]}"; do
        host_retry_count[$host]=0
    done

    # Function to run SCP operation
    run_scp() {
        local host="$1"
        local attempt="$2"
        local safe_host="${host//[^a-zA-Z0-9]/_}"
        local log_file="/tmp/pscp_${safe_host}_${attempt}.log"
        local exit_file="/tmp/pscp_exit_${safe_host}_${attempt}.code"
        
        echo "[$(date '+%H:%M:%S')] Attempt $attempt: $host" > "$log_file"
        
        # Execute SCP command
        local exit_code=0
        if [[ -n "$password" ]]; then
            # Use password with expect script
            local expect_script="/tmp/pscp_expect_${safe_host}_${attempt}.exp"
            cat > "$expect_script" << 'EOF'
#!/usr/bin/expect -f
set timeout $env(PSCP_TIMEOUT)
log_user 0
spawn {*}$env(PSCP_CMD)
expect {
    "password:" {
        send "$env(PSCP_PASSWORD)\r"
        exp_continue
    }
    "Password:" {
        send "$env(PSCP_PASSWORD)\r"
        exp_continue
    }
    "(yes/no)" {
        send "yes\r"
        exp_continue
    }
    "Are you sure" {
        send "yes\r"
        exp_continue
    }
    eof
}
catch wait result
set exit_code [lindex $result 3]
puts "EXPECT_EXIT_CODE:$exit_code"
EOF
            
            # Environment variables for expect
            PSCP_TIMEOUT="$((timeout + 30))" \
            PSCP_PASSWORD="$password" \
            PSCP_CMD="$scp_cmd ${scp_options[*]} $source_path $user@$host:$dest_path" \
            expect "$expect_script" >> "$log_file" 2>&1
            exit_code=$?
            
            if grep -q "EXPECT_EXIT_CODE:" "$log_file"; then
                local expect_exit=$(grep "EXPECT_EXIT_CODE:" "$log_file" | tail -1 | cut -d: -f2)
                if [[ "$expect_exit" =~ ^[0-9]+$ ]]; then
                    exit_code=$expect_exit
                fi
            fi
            
            rm -f "$expect_script"
        else
            eval "$scp_cmd ${scp_options[*]} \"$source_path\" \"$user@$host:$dest_path\"" >> "$log_file" 2>&1
            exit_code=$?
        fi
        
        echo "[$(date '+%H:%M:%S')] Completed: $host (Exit: $exit_code)" >> "$log_file"
        
        # Check for critical error messages in log file
        if [[ $exit_code -eq 0 ]]; then
            # SCP appears successful but check for critical errors in log
            # Exclude debug messages and look for real errors only
            if grep -v "^debug1:" "$log_file" | grep -qi "permission denied\|connection refused\|no such file or directory\|host key verification failed\|operation timed out\|authentication failed\|scp:.*error"; then
                echo "[$(date '+%H:%M:%S')] Critical error detected, exit code changed to 1" >> "$log_file"
                exit_code=1
            fi
        fi
        
        # Write exit code safely to file
        echo "$exit_code" > "$exit_file.tmp" && mv "$exit_file.tmp" "$exit_file"
        echo "[$(date '+%H:%M:%S')] Final exit code: $exit_code" >> "$log_file"
        
        exit $exit_code
    }

    # Function to check job completion
    check_completed_jobs() {
        local new_active_pids=()
        [[ "$debug_mode" == true ]] && echo "[DEBUG] Checking ${#active_pids[@]} active PIDs..."
        
        for pid in "${active_pids[@]}"; do
            # Ensure PID is not empty
            if [[ -z "$pid" ]]; then
                [[ "$debug_mode" == true ]] && echo "[DEBUG] Boş PID atlandı"
                continue
            fi
            
            if ! kill -0 "$pid" 2>/dev/null; then
                # Process finished - check if PID is in mapping
                local finished_host=""
                [[ "$debug_mode" == true ]] && echo "[DEBUG] PID $pid bitti, mapping kontrol ediliyor..."
                
                if [[ -v "pid_to_host[$pid]" ]] && [[ -n "${pid_to_host[$pid]}" ]]; then
                    finished_host="${pid_to_host[$pid]}"
                    [[ "$debug_mode" == true ]] && echo "[DEBUG] PID $pid -> Host: $finished_host"
                    
                    local safe_host="${finished_host//[^a-zA-Z0-9]/_}"
                    local exit_file="/tmp/pscp_exit_${safe_host}_1.code"
                    local exit_code=1  # Varsayılan olarak hata
                    
                    # Read exit code safely from file
                    if [[ -f "$exit_file" ]]; then
                        exit_code=$(cat "$exit_file" 2>/dev/null)
                        # Number validation
                        if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
                            exit_code=1
                        fi
                        rm -f "$exit_file" 2>/dev/null
                    fi
                    
                    if [[ $exit_code -eq 0 ]]; then
                        echo "✅ SUCCESS: $finished_host"
                        ((success_count++))
                        completed_hosts+=("$finished_host")
                    else
                        echo "❌ ERROR: $finished_host (Exit code: $exit_code)"
                        ((fail_count++))
                        failed_hosts+=("$finished_host")
                    fi
                    
                    # Clean up PID mapping
                    unset "pid_to_host[$pid]"
                else
                    # Orphan PID - this can be normal (race condition)
                    [[ "$debug_mode" == true ]] && echo "[DEBUG] Orphan PID: $pid (mapping'de bulunamadı)"
                    echo "⚠️ Orphan process finished: PID $pid"
                    ((fail_count++))
                fi
                ((running_jobs--))
            else
                # Still running, add to new array
                new_active_pids+=("$pid")
            fi
        done
        active_pids=("${new_active_pids[@]}")
        [[ "$debug_mode" == true ]] && echo "[DEBUG] Kalan aktif PID'ler: ${#active_pids[@]}"
    }

    # Start process for each host
    for host in "${hosts[@]}"; do
        # Max parallel control
        while [[ $running_jobs -ge $max_parallel ]]; do
            sleep 0.1
            check_completed_jobs
        done

        # Start new process
        {
            run_scp "$host" 1
        } &
        
        local pid=$!
        # Ensure PID is valid
        if [[ -n "$pid" ]] && [[ "$pid" =~ ^[0-9]+$ ]]; then
            pid_to_host[$pid]="$host"
            active_pids+=("$pid")
            ((running_jobs++))
            echo "🔄 Started: $host (PID: $pid) [Active: $running_jobs/$max_parallel]"
        else
            echo "❌ ERROR: Invalid PID for $host: $pid"
            ((fail_count++))
            failed_hosts+=("$host")
        fi
    done

    # Wait for remaining processes to complete
    echo "⏳ Completing remaining transfer operations..."
    while [[ ${#active_pids[@]} -gt 0 ]]; do
        sleep 0.5
        check_completed_jobs
        
        # Progress display
        if [[ ${#active_pids[@]} -gt 0 ]]; then
            echo "⏳ Pending processes: ${#active_pids[@]}"
        fi
    done

    # Retry logic - başarısız hostları tekrar dene
    if [[ $retry_count -gt 0 ]] && [[ $fail_count -gt 0 ]]; then
        echo ""
        echo "🔄 Retrying failed transfers (max $retry_count attempts)..."
        
        local retry_hosts=("${failed_hosts[@]}")
        local retry_success=0
        
        for ((retry=1; retry<=retry_count; retry++)); do
            if [[ ${#retry_hosts[@]} -eq 0 ]]; then
                break
            fi
            
            echo "🔄 Attempt $retry/${retry_count} - ${#retry_hosts[@]} hosts remaining"
            local current_retry_hosts=("${retry_hosts[@]}")
            retry_hosts=()
            local retry_pids=()
            declare -A retry_pid_to_host
            
            # Start retries in parallel
            for host in "${current_retry_hosts[@]}"; do
                echo "🔄 Retrying: $host (Attempt $((retry+1)))"
                
                # Execute SCP operation
                {
                    run_scp "$host" $((retry+1))
                } &
                
                local retry_pid=$!
                retry_pids+=("$retry_pid")
                retry_pid_to_host[$retry_pid]="$host"
            done
            
            # Wait for retry operations to complete
            for retry_pid in "${retry_pids[@]}"; do
                wait "$retry_pid"
                local host="${retry_pid_to_host[$retry_pid]}"
                local safe_host="${host//[^a-zA-Z0-9]/_}"
                local exit_file="/tmp/pscp_exit_${safe_host}_$((retry+1)).code"
                local exit_code=1
                
                # Read exit code from file
                if [[ -f "$exit_file" ]]; then
                    exit_code=$(cat "$exit_file" 2>/dev/null)
                    if ! [[ "$exit_code" =~ ^[0-9]+$ ]]; then
                        exit_code=1
                    fi
                    rm -f "$exit_file" 2>/dev/null
                fi
                
                if [[ $exit_code -eq 0 ]]; then
                    echo "✅ SUCCESS (Retry): $host"
                    ((retry_success++))
                    ((success_count++))
                    completed_hosts+=("$host")
                    ((fail_count--))
                    # Remove from failed hosts array
                    local temp_failed=()
                    for fh in "${failed_hosts[@]}"; do
                        if [[ "$fh" != "$host" ]]; then
                            temp_failed+=("$fh")
                        fi
                    done
                    failed_hosts=("${temp_failed[@]}")
                else
                    echo "❌ ERROR (Retry): $host"
                    retry_hosts+=("$host")
                fi
            done
            
            if [[ ${#retry_hosts[@]} -eq 0 ]]; then
                break
            fi
            
            if [[ $retry -lt $retry_count ]]; then
                echo "⏳ Waiting 2 seconds..."
                sleep 2
            fi
        done
        
        if [[ $retry_success -gt 0 ]]; then
            echo "✅ $retry_success hosts succeeded after retry"
        fi
    fi

    # Check for missing hosts (some hosts may not have been processed)
    local total_processed=$((success_count + fail_count))
    if [[ $total_processed -lt ${#all_hosts[@]} ]]; then
        local missing_count=$((${#all_hosts[@]} - total_processed))
        echo "⚠️ $missing_count hosts could not be processed (timeout or unexpected error)"
        ((fail_count += missing_count))
    fi

    # Show results
    echo ""
    echo "📊 RESULTS:"
    echo "========"
    
    if [[ $success_count -gt 0 ]]; then
        echo "✅ SUCCESSFUL ($success_count):"
        for host in "${completed_hosts[@]}"; do
            echo "   $host"
        done
    fi
    
    if [[ $fail_count -gt 0 ]]; then
        echo ""
        echo "❌ FAILED ($fail_count):"
        for host in "${failed_hosts[@]}"; do
            echo "   $host (Log: /tmp/pscp_${host//[^a-zA-Z0-9]/_}_*.log)"
        done
    fi

    echo ""
    echo "📈 SUMMARY:"
    echo "Successful: $success_count"
    echo "Failed: $fail_count"  
    echo "Total: ${#all_hosts[@]} hosts"

    # Clean up log files if not verbose
    local has_verbose=false
    for opt in "${scp_options[@]}"; do
        if [[ "$opt" == "-v" ]]; then
            has_verbose=true
            break
        fi
    done

    if [[ "$has_verbose" == false ]]; then
        for host in "${all_hosts[@]}"; do
            local safe_host="${host//[^a-zA-Z0-9]/_}"
            rm -f "/tmp/pscp_${safe_host}_*.log" 2>/dev/null
            rm -f "/tmp/pscp_exit_${safe_host}_*.code" 2>/dev/null
            rm -f "/tmp/pscp_expect_${safe_host}_*.exp" 2>/dev/null
        done
    else
        echo ""
        echo "📝 Log files saved in /tmp/ directory:"
        for host in "${all_hosts[@]}"; do
            local safe_host="${host//[^a-zA-Z0-9]/_}"
            for log_file in "/tmp/pscp_${safe_host}_*.log"; do
                if [[ -f "$log_file" ]]; then
                    echo "   $log_file"
                fi
            done
        done
    fi

    # Return exit code 1 if there are failed transfers
    [[ $fail_count -eq 0 ]] && return 0 || return 1
}

# Auto completion support
_parallel_scp() {
    local context state state_descr line
    typeset -A opt_args

    _arguments \
        '-h[hosts file]:file:_files' \
        '--hosts[hosts file]:file:_files' \
        '-u[user]:user:_users' \
        '--user[user]:user:_users' \
        '-P[port]:port:' \
        '-t[timeout]:timeout:' \
        '--timeout[timeout]:timeout:' \
        '--max-parallel[max parallel]:number:' \
        '--retry[retry count]:number:' \
        '--dry-run[dry run]' \
        '--password[password]:password:' \
        '--ask-pass[ask password]' \
        '-C[compress]' \
        '-r[recursive]' \
        '-v[verbose]' \
        '-q[quiet]' \
        '-p[preserve]' \
        '-B[batch mode]' \
        '-1[protocol 1]' \
        '-2[protocol 2]' \
        '-4[IPv4]' \
        '-6[IPv6]' \
        '-c[cipher]:cipher:' \
        '-F[config file]:file:_files' \
        '-i[identity file]:file:_files' \
        '-l[limit]:limit:' \
        '-o[ssh option]:option:' \
        '-S[program]:program:_command_names' \
        '*:file:_files'
}

compdef _parallel_scp parallel_scp