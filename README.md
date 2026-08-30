# serverctl ( English )

Documentation version: v1.1.16 (2026-08-31)

`serverctl` is a lightweight web hosting manager for Ubuntu Server. It manages Nginx, isolated PHP-FPM pools, MariaDB, Let's Encrypt, UFW, AppArmor, backups, updates, health checks, and security audits. An optional PHP/Nginx Dashboard is available without adding Node.js or an administration daemon.

## Principles

- One Linux user and one PHP-FPM pool per website
- Validated arguments and allow-listed system commands
- Backup, validate, apply, health-check, and rollback configuration flow
- Confirmation for destructive actions; `--yes` for explicit automation
- Audit every CLI action without logging passwords, tokens, or private keys
- Install only required packages; expose only SSH, HTTP, and HTTPS
- Keep the Dashboard disabled until an administrator supplies a domain, localhost, or LAN IP; public deployments require an HTTPS certificate

## Quick start

```bash
sudo bash install.sh --profile minimal --php 8.3
sudo serverctl health
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

For Ubuntu 22.04, or multi-PHP on Ubuntu 24.04, review the third-party repository note in [INSTALL.md](INSTALL.md). Do not deploy directly to production before testing on a disposable Ubuntu VM and confirming restore procedures.

## Documentation

- [How to install](How%20to%20install.md)
- [Installation](INSTALL.md)
- [CLI reference](CLI.md)
- [Architecture](ARCHITECTURE.md)
- [Security model](SECURITY.md)
- [Backup and restore](BACKUP.md)
- [Updates](UPDATE.md)
- [Nginx management](NGINX.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Web Dashboard](DASHBOARD.md)

The interactive CLI interface has 14 main choices, including Database Management and SFTP Users. The optional Web Dashboard is a separate PHP-FPM application and is not added as a CLI menu item.

## Getting started

Read the installation guide in [How to install](How%20to%20install.md).

---

# serverctl ( ไทย )

เวอร์ชันเอกสาร: v1.1.16 (31-08-2026)

`serverctl` คือระบบจัดการเว็บโฮสติ้งแบบเบาสำหรับ Ubuntu Server ใช้จัดการ Nginx, PHP-FPM pool แบบแยกเว็บไซต์, MariaDB, Let's Encrypt, UFW, AppArmor, การสำรองข้อมูล, การอัปเดต, การตรวจสอบสุขภาพระบบ และการตรวจสอบความปลอดภัย นอกจากนี้ยังมี Dashboard แบบ PHP/Nginx ให้ใช้งานโดยไม่ต้องติดตั้ง Node.js หรือ daemon สำหรับจัดการระบบ

## หลักการทำงาน

- ใช้ Linux user และ PHP-FPM pool แยกสำหรับแต่ละเว็บไซต์
- ตรวจสอบ argument และอนุญาตเฉพาะคำสั่งระบบที่กำหนดไว้
- สำรองข้อมูล ตรวจสอบ ใช้งาน ตรวจสุขภาพ และ rollback configuration ตามลำดับ
- ยืนยันก่อนการทำงานที่ลบหรือทำลายข้อมูล และใช้ `--yes` สำหรับ automation ที่ระบุชัดเจน
- บันทึก audit ของ CLI โดยไม่เก็บ password, token หรือ private key
- ติดตั้งเฉพาะแพ็กเกจที่จำเป็น และเปิดเผยเฉพาะ SSH, HTTP และ HTTPS
- ปิด Dashboard ไว้จนกว่าผู้ดูแลระบบจะกำหนด domain, localhost หรือ LAN IP โดยการใช้งานผ่าน domain สาธารณะต้องมี HTTPS certificate

## เริ่มต้นใช้งานอย่างรวดเร็ว

```bash
sudo bash install.sh --profile minimal --php 8.3
sudo serverctl health
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

สำหรับ Ubuntu 22.04 หรือการใช้หลาย PHP บน Ubuntu 24.04 ให้อ่านหมายเหตุเรื่อง repository ภายนอกใน [INSTALL.md](INSTALL.md) ไม่ควรนำไปใช้บน production โดยตรงก่อนทดสอบบน Ubuntu VM ชั่วคราวและตรวจสอบขั้นตอน restore

## เอกสาร

- [วิธีติดตั้ง](How%20to%20install.md)
- [การติดตั้ง](INSTALL.md)
- [คู่มือ CLI](CLI.md)
- [สถาปัตยกรรม](ARCHITECTURE.md)
- [รูปแบบความปลอดภัย](SECURITY.md)
- [การสำรองและกู้คืน](BACKUP.md)
- [การอัปเดต](UPDATE.md)
- [การจัดการ Nginx](NGINX.md)
- [การแก้ไขปัญหา](TROUBLESHOOTING.md)
- [Web Dashboard](DASHBOARD.md)

เมนู CLI แบบโต้ตอบมี 14 รายการหลัก รวม Database Management และ SFTP Users ส่วน Web Dashboard เป็นแอปพลิเคชัน PHP-FPM แยกต่างหากและไม่ได้เพิ่มเป็นรายการในเมนู CLI

## เริ่มติดตั้ง

อ่านคู่มือการติดตั้งภาษาอังกฤษได้ที่ [How to install](How%20to%20install.md)
