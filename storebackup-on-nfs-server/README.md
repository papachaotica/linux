# StoreBackup on NFS server

This package provides generic, guarded StoreBackup helpers for an NFS backup
server. It writes incremental data with `lateLinks=yes`;
the ASR server is responsible for running `storeBackupUpdateBackup` later.

## Safety defaults

- `doNotDelete=yes`: no old backup is deleted.
- No configuration is installed below `/etc`; installing the package cannot
  start a backup. Copy and adapt both files from
  `/usr/share/doc/storebackup-on-nfs-server/examples/` deliberately.

The `precommand` refuses to run if `/net/backup` is mounted from a source
other than `asr.lan:/mnt/backup`. If it mounted the export itself, the
`postcommand` unmounts it after a successful run. Existing mounts are left
untouched.

## Build

From this repository root:

```sh
dpkg-buildpackage -us -uc -b
```

The resulting `.deb` is written to the parent directory.

## First verification run

After installing the package, inspect the resolved configuration without
copying data:

```sh
sudo storeBackup -f /etc/storebackup.d/my-client --print
```

Then run one backup manually and inspect its log and
`.storeBackup.notSaved.bz2` before enabling the timer:

```sh
sudo storeBackup -f /etc/storebackup.d/my-client
```
