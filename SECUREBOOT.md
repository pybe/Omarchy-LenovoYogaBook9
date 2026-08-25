# Secure Boot and TPM unlock

**Status: Secure Boot enabled and verified. TPM enrolled and the initramfs switched — awaiting a reboot to confirm auto-unlock.**

## Why bother

This machine has no built-in keyboard, and a Bluetooth one cannot answer the LUKS passphrase prompt because the initramfs has no Bluetooth stack (see the Open items in the [README](README.md)). So every boot needs a USB keyboard, typing into a prompt that renders upside down.

TPM unlock removes the prompt entirely, which solves both problems at once. But binding to the TPM is materially weaker without Secure Boot: PCR policy is only meaningful if unsigned code cannot boot and satisfy the same policy. Hence Secure Boot first, TPM second.

Omarchy, like most Arch-based installers, is not signed with keys the firmware trusts, so Secure Boot has to be turned off to install it. Getting it back on means enrolling your own keys and signing your own boot files.

There is no `omarchy` command for this — `omarchy setup security` covers fido2, fingerprint, sshd and sudoless docker only. `sbctl` is not installed by default.

## What has to be signed on this machine

```
/boot/EFI/BOOT/BOOTX64.EFI          limine, fallback path
/boot/EFI/limine/limine_x64.efi     limine
/boot/EFI/Linux/omarchy_linux.efi   the UKI (kernel + initramfs + cmdline)
```

Plus any rollback images, which are easy to miss and will refuse to boot under Secure Boot if unsigned:

```
/boot/<machine-id>/limine_history/omarchy_linux.efi_sha256_*
```

`sbctl verify` catches these — it flagged the history image after the three obvious ones were done.

## Done so far

```bash
pacman -S --needed sbctl
sbctl create-keys
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/EFI/limine/limine_x64.efi
sbctl sign -s /boot/EFI/Linux/omarchy_linux.efi
find /boot -path '*limine_history*' -name '*.efi_sha256_*' -exec sbctl sign {} \;
sbctl verify        # all green
```

`-s` records each file in sbctl's database so it is re-signed automatically on updates. That matters because limine rebuilds the UKI on every kernel update. The hook ordering works out — `zz-sbctl.hook` sorts after limine's `80-limine-efi-deploy.hook` and `90-limine-mkinitcpio-remove-post.hook`, so the UKI is signed after it is rebuilt, not before:

```
10-limine-snapper-lock.hook
60-limine-mkinitcpio-remove-pre.hook
80-limine-efi-deploy.hook
90-limine-mkinitcpio-remove-post.hook
zz-sbctl.hook
```

## Signing breaks limine's hash pinning — sign first, then rewrite hashes

This is the trap on an Omarchy/limine system, and it bites immediately.

`limine.conf` pins each bootable file by blake2b checksum, appended to the path with `#`:

```
path: boot():/EFI/Linux/omarchy_linux.efi#71af4420bf12602e6442aab2a6be9773...
hash_mismatch_panic: no
```

Signing appends a signature, which changes the file, which invalidates that hash. The next boot throws **"blake2b hash for uri does not match"**. It is a warning rather than a dead machine only because Omarchy ships `hash_mismatch_panic: no` — do not assume that is true on another setup.

The fix is ordering: sign, then regenerate the config so the recorded hashes describe the signed files.

```bash
limine-update      # rewrite limine.conf
sbctl sign-all     # re-sign anything that lost its signature
limine-update      # rewrite again, now describing the signed files
sbctl verify
```

Confirm rather than assume, since the failure mode is a boot-time error:

```bash
recorded=$(grep -m1 'omarchy_linux.efi#' /boot/limine.conf | sed 's/.*#//')
actual=$(b2sum /boot/EFI/Linux/omarchy_linux.efi | cut -d' ' -f1)
[ "$recorded" = "$actual" ] && echo MATCH || echo MISMATCH
```

**`limine-update` re-deploys `/boot/EFI/BOOT/BOOTX64.EFI` unsigned.** Running it strips that file's signature, so sign it again afterwards and check with `sbctl verify`. Package upgrades are unaffected — `zz-sbctl.hook` sorts after limine's `80-limine-efi-deploy.hook` — but a manual `limine-update` leaves the bootloader unsigned until you re-sign it. That would be a failure to boot once Secure Boot is on.

## Remaining steps

1. ~~**BIOS:** clear/erase keys to reach Setup Mode, leaving Secure Boot off.~~ **Done.** On this Insyde firmware the option sits under Security → Secure Boot. `sbctl status` then reported `Setup Mode: Enabled`, `Vendor Keys: none`.
2. ~~**Enrol:** `sbctl enroll-keys -m`.~~ **Done.** The `-m` keeps Microsoft's vendor keys, which matters on a Lenovo — firmware capsule updates and option ROMs are signed with them, and dropping them can break firmware updates. Status afterwards: `Setup Mode: Disabled`, `Vendor Keys: microsoft`.
3. **BIOS again:** enable Secure Boot. Confirm with `bootctl status` (`Secure Boot: enabled`) or `sbctl status`. **← next**
4. ~~**TPM:**~~ **Done, pending reboot.** See below. That needs the initramfs switched from the `encrypt` hook to `sd-encrypt`, the `cryptdevice=` parameter replaced with `rd.luks.*`, and `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`. PCR 7 is the Secure Boot state, which is the whole point of doing it in this order. Keep the passphrase keyslot as a fallback.

Keep a USB keyboard attached throughout: firmware setup and the LUKS prompt both need one.

## Escape hatch

If anything refuses to boot, go into the BIOS and turn Secure Boot off. That restores exactly the previous behaviour. Signing and key creation are inert while Secure Boot is disabled.

## Firmware state on this machine

```
Firmware:     UEFI 2.80 (INSYDE Corp. 321.00)
Secure Boot:  disabled
Setup Mode:   disabled          <- must become enabled before enrolling
Vendor Keys:  microsoft builtin-db builtin-db builtin-PK
TPM2:         present (/dev/tpm0), LUKS2 root, no TPM token enrolled
```


## TPM unlock

Enrol the TPM against PCR 7 (Secure Boot state — the reason for doing Secure Boot first). This needs the existing passphrase typed interactively, and it **adds** a keyslot rather than replacing one, so the passphrase remains as a fallback:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 /dev/nvme0n1p2
```

Confirm with `cryptsetup luksDump` — expect two keyslots and a `systemd-tpm2` token:

```
Keyslots:  0: luks2      1: luks2
Tokens:    0: systemd-tpm2
```

The busybox `encrypt` hook cannot talk to a TPM, so the initramfs must move to `sd-encrypt`. Omarchy's hooks live in `/etc/mkinitcpio.conf.d/omarchy_hooks.conf`; rather than editing that package-managed file, add a later-sorting drop-in — `zz-sd-encrypt.conf` — which wins because mkinitcpio sources drop-ins in sort order:

```bash
HOOKS=(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck btrfs-overlayfs)
```

`udev` becomes `systemd`, `keymap`+`consolefont` become `sd-vconsole`, `encrypt` becomes `sd-encrypt`. The `resume` hook that `omarchy_resume.conf` appends is dropped deliberately: under the systemd hook, hibernation resume is handled by `systemd-hibernate-resume-generator` from the `resume=` parameter, which is still supplied.

Then swap the root parameter in `/etc/default/limine`:

```
cryptdevice=PARTUUID=<part>:root   ->   rd.luks.name=<luks-uuid>=root
```

Rebuild and re-sign, minding the hash ordering described above:

```bash
limine-mkinitcpio     # rebuilds the UKI, rewrites limine.conf
sbctl sign-all
limine-update         # rewrite hashes to describe the signed UKI
sbctl sign -s /boot/EFI/BOOT/BOOTX64.EFI   # limine-update stripped this
sbctl verify
```

### The UKI carries no embedded command line

Worth knowing before assuming a UKI implies a signed command line. On this setup it does not:

```
$ objdump -h /boot/EFI/Linux/omarchy_linux.efi
  .osrel   .linux   .initrd        <- no .cmdline
```

limine passes the command line externally via `cmdline:` entries in `limine.conf`, and that is honoured even with Secure Boot enabled — confirmed by `/proc/cmdline` matching limine's entry on a Secure Boot run. This is deliberate on limine-snapper-sync's part: snapshot entries need to override `rootflags=subvol=`, which an embedded command line would forbid.

**Security consequence, stated plainly.** `limine.conf` is not signed. Anyone with physical access can edit the command line it passes, and PCR 7 only measures Secure Boot policy — not the command line — so the TPM would still release the key. TPM unlock here therefore protects a stolen drive well, and protects less against someone who has the whole machine. Binding additional PCRs, or accepting a TPM PIN, would tighten it at the cost of convenience. Not done here.

### Rollback

The Snapshots entry points at the previous UKI in `limine_history`, paired with the old `cryptdevice=` command line, and that image is signed. Old kernel, old initramfs, old parameter — a matched set, so it boots and prompts for the passphrase. Keep a USB keyboard around for it: Bluetooth still will not work at that prompt.
