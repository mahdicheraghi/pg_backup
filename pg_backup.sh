#!/bin/bash
set -eo pipefail

# --------------------------
# Configurable Variables
# --------------------------
# PostgreSQL Configuration
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="postgres"
DB_PASS="your_db_password"
DB_NAME="mydb"
SCHEMAS=("schema1" "schema2")  # Schemas to backup

# Backup Configuration
BACKUP_ROOT="/path/to/backups"
DAILY_DIR="$BACKUP_ROOT/daily"
WEEKLY_DIR="$BACKUP_ROOT/weekly"
MONTHLY_DIR="$BACKUP_ROOT/monthly"
GZIP_THREADS=4
LOG_FILE="/var/log/pg_backup.log"

# SSH Configuration
REMOTE_ENABLE=false
REMOTE_HOST="remote.example.com"
REMOTE_USER="user"
REMOTE_PASS="your_ssh_password"
REMOTE_DIR="/remote/backup/path"
REMOTE_PORT="22"

# Retention Policies
DAILY_RETENTION_DAYS=7
WEEKLY_RETENTION_DAYS=28
MONTHLY_RETENTION_DAYS=365

# Progress Tracking
TOTAL_STEPS=5
CURRENT_STEP=1

# --------------------------
# Helper Functions
# --------------------------
log() {
    # Log messages with timestamp
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    # Handle critical errors
    log "ERROR: $1"
    exit 1
}

show_progress() {
    # Display progress messages on stderr
    local step=$1
    local message=$2
    printf "\rProgress: [%d/%d] %s" "$step" "$TOTAL_STEPS" "$message" >&2
}

check_prerequisites() {
    # Verify required tools are installed
    show_progress $CURRENT_STEP "Checking prerequisites"
    local missing=()
    
    { command -v pg_dump && command -v pigz && command -v sshpass; } >/dev/null 2>&1 || {
        log "Missing dependencies:"
        echo "For Debian/Ubuntu:"
        echo "  sudo apt-get install postgresql-client pigz sshpass pv"
        echo "For RHEL/CentOS:"
        echo "  sudo yum install postgresql pigz sshpass pv"
        error_exit "Required packages missing"
    }
    
    ((CURRENT_STEP++))
}

# --------------------------
# Backup Function
# --------------------------
perform_backup() {
    local schema=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_base="${schema}_${timestamp}"
    local tmp_dir=$(mktemp -d)
    
    show_progress $CURRENT_STEP "Backing up $schema schema"
    
    # Dump database with progress tracking
    { PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
        -n "$schema" -Fp \
        | pv -N "Dumping $schema" -petr \
        | pigz -9 -p $GZIP_THREADS > "${tmp_dir}/${backup_base}.sql.gz"; } || {
            rm -rf "$tmp_dir"
            error_exit "Failed to backup schema $schema"
        }

    # Generate SHA1 checksum
    show_progress $((CURRENT_STEP+1)) "Generating checksum"
    sha1sum "${tmp_dir}/${backup_base}.sql.gz" | awk '{print $1}' > "${tmp_dir}/${backup_base}.sha1"

    # Create final tar archive
    show_progress $((CURRENT_STEP+2)) "Creating final package"
    tar cf "${backup_base}.tar" -C "$tmp_dir" "${backup_base}.sql.gz" "${backup_base}.sha1" || {
        rm -rf "$tmp_dir"
        error_exit "Tar creation failed"
    }

    rm -rf "$tmp_dir"
    ((CURRENT_STEP+=3))
    
    # Output sanitized filename
    echo "$backup_base.tar" | tr -d '\r'
}

# --------------------------
# Retention Management
# --------------------------
manage_retention() {
    # Apply retention policies
    show_progress $CURRENT_STEP "Applying retention policies"
    
    # Daily retention
    find "$DAILY_DIR" -type f -name "*.tar" -mtime +$DAILY_RETENTION_DAYS -delete
    
    # Weekly retention
    find "$WEEKLY_DIR" -type f -name "*.tar" -mtime +$WEEKLY_RETENTION_DAYS -delete
    
    # Monthly retention
    find "$MONTHLY_DIR" -type f -name "*.tar" -mtime +$MONTHLY_RETENTION_DAYS -delete
    
    ((CURRENT_STEP++))
}

# --------------------------
# Main Execution
# --------------------------
{
    check_prerequisites
    mkdir -p {$DAILY_DIR,$WEEKLY_DIR,$MONTHLY_DIR}

    for schema in "${SCHEMAS[@]}"; do
        log "Starting backup for schema: $schema"
        backup_file=$(perform_backup "$schema")
        final_path="$DAILY_DIR/$backup_file"
        mv "$backup_file" "$final_path"

        # Classify backups by date
        backup_date=$(date -d "$(echo "$backup_file" | grep -oE '[0-9]{8}')" +%s)
        
        # Weekly backups (every Wednesday)
        if [ $(date -d @$backup_date +%u) -eq 3 ]; then
            cp "$final_path" "$WEEKLY_DIR/"
        fi
        
        # Monthly backups (first day of month)
        if [ $(date -d @$backup_date +%d) -eq 01 ]; then
            cp "$final_path" "$MONTHLY_DIR/"
        fi

        # Remote transfer
        if $REMOTE_ENABLE; then
            show_progress $CURRENT_STEP "Transferring to remote"
            sshpass -p "$REMOTE_PASS" scp -P "$REMOTE_PORT" "$final_path" \
            "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" || log "Remote transfer failed for $backup_file"
        fi
    done

    manage_retention
    echo -e "\nBackup completed successfully"
} | tee -a "$LOG_FILE"
