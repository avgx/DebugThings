# Design

## Context

Each SwiftLog label gets its own handler instance, and every instance opens the same path with `O_APPEND`. A rename-based rotation would leave the other instances writing to the renamed inode, so rotation must keep the inode and truncate it.

## Decisions

**Copy then truncate, same inode.** Under the shared write lock, the handler reads the active file, writes it to `<name>.1` atomically, and calls `ftruncate(fd, 0)` on its own descriptor. All other `O_APPEND` descriptors on that inode continue at the new end, so no handler needs to reopen the file.

**Size from `fstat`, not a counter.** The check uses the file size reported by the descriptor, so it stays correct when the file was already larger at startup or was appended to by another handler.

**Rotate before writing, not after.** A write that would exceed the cap triggers rotation first. The active file therefore never exceeds the cap, except for one oversized line.

**Shared lock.** `FileLogHandler.writeLock` becomes internal and is reused, so plain and rolling handlers on the same path also serialize.

**Process scope.** The lock is in-process. Two processes writing the same file can race a rotation. The app in question logs from one process, so this is accepted and documented.

**Opt-in.** `bootstrapFile` keeps `maxFileBytes: nil` as the default, so existing callers see no change.

**Descriptor is read-write.** Rotation reads the active file through the handler's own descriptor, so that descriptor is opened `O_RDWR | O_APPEND`. A write-only descriptor makes the read fail, which would leave the backup empty; the tests cover this.

**Backup failure keeps the cap.** If writing `<name>.1` fails, the active file is still truncated. The cap is the hard contract, so the previous backup is lost in that case rather than letting the file grow.

## Risks

- Cross-process rotation is not safe. Accepted; see above.
- The backup copy reads the whole active file under the lock. At 16 KiB this is negligible.
- Logging from a signal handler is not supported. Rotation allocates and uses Foundation.
