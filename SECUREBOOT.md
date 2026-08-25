# Secure Boot and TPM unlock

**Status: in progress.** Keys are created and every boot binary is signed. Firmware key enrolment and Secure Boot itself are not done yet. Nothing here changes how the machine boots today — signed binaries boot normally with Secure Boot disabled.

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

## Remaining steps

1. **BIOS:** F2 at boot (or the Novo pinhole). Security → Secure Boot → clear/erase keys, often worded "Reset to Setup Mode". Leave Secure Boot **off**. Save, exit, boot normally. `sbctl status` should then report `Setup Mode: Enabled`.
2. **Enrol:** `sbctl enroll-keys -m`. The `-m` keeps Microsoft's vendor keys, which matters on a Lenovo — firmware capsule updates and option ROMs are signed with them, and dropping them can break firmware updates.
3. **BIOS again:** enable Secure Boot. Confirm with `bootctl status` (`Secure Boot: enabled`) or `sbctl status`.
4. **TPM:** then, and only then, enrol the TPM for LUKS. That needs the initramfs switched from the `encrypt` hook to `sd-encrypt`, the `cryptdevice=` parameter replaced with `rd.luks.*`, and `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7`. PCR 7 is the Secure Boot state, which is the whole point of doing it in this order. Keep the passphrase keyslot as a fallback.

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
