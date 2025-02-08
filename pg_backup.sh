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
SCHEMAS=("schema1" "schema2")

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
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

show_progress() {
    local step=$1
    local message=$2
    echo -ne "Progress: [$step/$TOTAL_STEPS] $message\r"
}

check_prerequisites() {
    show_progress $CURRENT_STEP "Checking prerequisites"
    local missing=()
    
    { command -v pigz && command -v pg_dump && command -v sshpass; } >/dev/null 2>&1 || {
        log "Missing dependencies:"
        echo "For Debian/Ubuntu:"
        echo "  sudo apt-get install postgresql-client pigz sshpass"
        echo "For RHEL/CentOS:"
        echo "  sudo yum install postgresql pigz sshpass"
        error_exit "Required packages missing"
    }
    
    ((CURRENT_STEP++))
}

# --------------------------
# Backup Function with Progress
# --------------------------
perform_backup() {
    local schema=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_base="${schema}_${timestamp}"
    local tmp_dir=$(mktemp -d)
    
    show_progress $CURRENT_STEP "Backing up $schema schema"
    
    # Dump with progress estimation
    { PGPASSWORD="$DB_PASS" pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -n "$schema" -Fp \
        | pv -N "Dumping $schema" -petr \
        | pigz -9 -p $GZIP_THREADS > "${tmp_dir}/${backup_base}.sql.gz"; } || error_exit "Failed to backup schema $schema"

    # Generate SHA1
    show_progress $((CURRENT_STEP+1)) "Generating checksum"
    sha1sum "${tmp_dir}/${backup_base}.sql.gz" | awk '{print $1}' > "${tmp_dir}/${backup_base}.sha1"

    # Create tar archive
    show_progress $((CURRENT_STEP+2)) "Creating final package"
    tar cf "${backup_base}.tar" -C "$tmp_dir" "${backup_base}.sql.gz" "${backup_base}.sha1" || error_exit "Tar creation failed"

    rm -rf "$tmp_dir"
    ((CURRENT_STEP+=3))
    echo "$backup_base.tar"
}

# --------------------------
# Retention Management
# --------------------------
manage_retention() {
    show_progress $CURRENT_STEP "Applying retention policies"
    
    # Daily retention
    find "$DAILY_DIR" -type f -name "*.tar" -mtime +$DAILY_RETENTION_DAYS -exec rm -f {} \;
    
    # Weekly retention
    find "$WEEKLY_DIR" -type f -name "*.tar" -mtime +$WEEKLY_RETENTION_DAYS -exec rm -f {} \;
    
    # Monthly retention
    find "$MONTHLY_DIR" -type f -name "*.tar" -mtime +$MONTHLY_RETENTION_DAYS -exec rm -f {} \;
    
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

        # Classify backups
        backup_date=$(date -d "$(echo "$backup_file" | grep -oE '[0-9]{8}')" +%s)
        
        # Weekly (every Wednesday)
        if [ $(date -d @$backup_date +%u) -eq 3 ]; then
            cp "$final_path" "$WEEKLY_DIR/"
        fi
        
        # Monthly (first day)
        if [ $(date -d @$backup_date +%d) -eq 01 ]; then
            cp "$final_path" "$MONTHLY_DIR/"
        fi

        # Remote transfer
        if $REMOTE_ENABLE; then
            show_progress $CURRENT_STEP "Transferring to remote"
            sshpass -p "$REMOTE_PASS" scp -P "$REMOTE_PORT" "$final_path" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" \
            || log "Remote transfer failed for $backup_file"
        fi
    done

    manage_retention
    echo -e "\nBackup completed successfully"
} | tee -a "$LOG_FILE"
