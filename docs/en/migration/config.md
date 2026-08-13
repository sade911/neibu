# Configuration Migration Guide

This guide explains how to migrate configuration files from v2board to Xboard. Xboard stores configurations in the database instead of files.

### 1. Prepare Configuration File

```bash
# Copy old configuration file
cp old-project-path/config/v2board.php config/v2board.php
```

### 2. Execute Migration

```bash
php artisan migrateFromV2b config
```

### Important Notes

- After modifying the admin path, restart the Octane daemon process