
**Description:**  
Enterprise PostgreSQL backup solution with GPLv3 license. Features parallel compression, multi-schema support, and encrypted SSH transfers. Includes retention policies (daily/weekly/monthly) and integrity checks. Ideal for DevOps teams on Ubuntu/RHEL/CentOS.

# PostgreSQL Backup Automation Script

[![GPLv3 License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Open Source](https://img.shields.io/badge/Open%20Source-Yes-brightgreen)](https://opensource.org/)
[![Shell Check](https://img.shields.io/badge/Shell_Check-Validated-brightgreen)](https://github.com/koalaman/shellcheck)

An enterprise-grade PostgreSQL database backup solution with intelligent retention policies, parallel processing, and progress tracking.

## Key Features ✨

- **Multi-Schema Support** - Backup individual schemas
- **Smart Retention Policies**  
  📅 Daily (7 days)  
  📆 Weekly (4 weeks)  
  📅 Monthly (12 months)
- **Parallel Compression** - Multi-core GZIP via `pigz`
- **Progress Tracking** - Real-time monitoring with `pv`
- **SSH File Transfer** - Encrypted remote backups
- **Checksum Verification** - SHA1 integrity checks
- **Cross-Platform** - Supports Debian, Ubuntu, RHEL, CentOS
- **Error Handling** - Fail-safes with detailed logging

## Installation ⚙️

### Prerequisites

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install postgresql-client pigz sshpass pv

# RHEL/CentOS
sudo yum install postgresql pigz sshpass pv
```

### Configuration

1. Edit the configuration section in `pg_backup.sh`:

```bash
# PostgreSQL Settings
DB_PASS="your_database_password"
SCHEMAS=("sales" "inventory")

# Path Configuration
BACKUP_ROOT="/var/backups/postgres"

# Remote Transfer Settings
REMOTE_ENABLE=true
REMOTE_HOST="backup.example.com"
REMOTE_USER="backup_user"
```

## Usage 🚀

Basic execution:
```bash
chmod +x pg_backup.sh
./pg_backup.sh
```

Sample output:
```
[2023-08-20 14:30:00] Starting backup for schema: sales
Progress: [2/5] Backing up sales schema
 10GiB 0:05:23 [32.5MiB/s] [================================>] 100%
[2023-08-20 14:35:23] Backup completed successfully
```

### Cron Job Setup
```bash
# Daily at 2 AM
0 2 * * * /path/to/pg_backup.sh >> /var/log/pg_backup.log 2>&1
```

## Directory Structure 📂
```
/var/backups/postgres/
├── daily/      # Last 7 days of backups
├── weekly/     # Last 4 weekly backups
└── monthly/    # Last 12 monthly backups
```

## Security Best Practices 🔒
1. **Credential Management**
   ```bash
   chmod 700 pg_backup.sh
   echo "localhost:5432:*:postgres:your_password" > ~/.pgpass
   chmod 600 ~/.pgpass
   ```

2. **SSH Key Authentication**
   ```bash
   ssh-keygen -t ed25519
   ssh-copy-id -i ~/.ssh/id_ed25519.pub backup_user@backup.example.com
   ```

## License 📜
This project is licensed under the **GNU General Public License v3.0**.  
**Key Requirements:**
- Source code must be disclosed
- Derivative works must use same license
- License text must be included in distributions

Full license text: [LICENSE](LICENSE)

## Contributing 🤝
Contributions are welcome under these terms:
1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

**Note:** All contributions must be licensed under GPL v3.0.

---

**Download Links**  
- [Download README.md](https://raw.githubusercontent.com/mahdicheraghi/pg_backup/README.md)  
- [Download Full Script](https://raw.githubusercontent.com/mahdicheraghi/pg_backup/refs/heads/main/pg_backup.sh)
