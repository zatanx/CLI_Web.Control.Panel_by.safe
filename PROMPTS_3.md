
==================================================
MENU 12.ตอนนี้ SYSTEM UPDATE
==================================================

เพิ่มเมนู:

12. System Update

เมื่อลูกค้าเลือกเมนู 12 ให้แสดง:

========================================
          SYSTEM UPDATE
========================================

  1. Check for Updates
  2. Security Updates
  3. Install Updates
  4. Update History
  5. System Health Check
  6. Reboot Required Status

  0. Back

========================================
Select option:


==================================================
1. CHECK FOR UPDATES
==================================================

เมนู:

1. Check for Updates

ตรวจสอบ Ubuntu Package Updates โดยไม่ติดตั้ง

ใช้ APT ที่มีอยู่ในระบบ

เช่น:

apt update

จากนั้นตรวจสอบ:

apt list --upgradable

แสดง:

========================================
         AVAILABLE UPDATES
========================================

Package                     Current       New
------------------------------------------------
nginx                       1.x.x         1.x.x
openssl                     3.x.x         3.x.x
php8.x-fpm                  8.x.x         8.x.x

Security Updates : X
Other Updates    : X

========================================

ต้องแยก:

- Security Updates
- Normal Updates

ห้ามติดตั้ง Update จากเมนูนี้


==================================================
2. SECURITY UPDATES
==================================================

เมนู:

2. Security Updates

แสดงเฉพาะ Package ที่เป็น Security Update

ก่อนติดตั้งต้อง:

1. ตรวจ Disk Space
2. ตรวจ RAM
3. ตรวจ Running Services
4. ตรวจ Nginx Configuration
5. ตรวจ PHP-FPM
6. ตรวจ MariaDB
7. ตรวจ Website Status
8. Backup Configuration

จากนั้นแสดง:

========================================
        SECURITY UPDATES
========================================

Security Updates Found: X

Package                     Current       New
------------------------------------------------
openssl                     x.x.x         x.x.x
libssl                      x.x.x         x.x.x
nginx                       x.x.x         x.x.x

========================================

ถาม:

Install Security Updates? [y/N]

ห้ามติดตั้งโดยไม่มี Confirmation


==================================================
3. INSTALL UPDATES
==================================================

เมนู:

3. Install Updates

ก่อนติดตั้งต้องทำ Pre-Update Check

ตรวจสอบ:

- Ubuntu Version
- Kernel Version
- Disk Space
- RAM
- CPU Load
- Nginx Status
- Nginx Configuration
- PHP-FPM Status
- MariaDB Status
- SSL Status
- Website Status

ตัวอย่าง:

========================================
          PRE-UPDATE CHECK
========================================

Ubuntu        : PASS
Disk Space    : PASS
Memory        : PASS
Nginx         : PASS
Nginx Config  : PASS
PHP-FPM       : PASS
MariaDB       : PASS
SSL           : PASS
Websites      : PASS

========================================

หากมี Critical Error:

ห้าม Update

แสดง:

[CRITICAL]
System is not ready for update.


==================================================
4. PRE-UPDATE BACKUP
==================================================

ก่อนติดตั้ง Update ต้อง Backup Configuration

อย่างน้อย:

/etc/nginx/
/etc/php/
/etc/mysql/

และ Configuration ของ Web Server Manager

เก็บ Backup:

/var/backups/serverctl/system-update/

ตัวอย่าง:

/var/backups/serverctl/system-update/
└── 2026-08-14_140000/

บันทึก:

- Date
- Time
- Ubuntu Version
- Kernel Version
- Package List
- User
- Source IP

หากระบบหลักมี Backup Module อยู่แล้ว
ให้เรียกใช้ Backup Module เดิม
และห้ามสร้างระบบ Backup ซ้ำโดยไม่จำเป็น


==================================================
5. SHOW UPDATE SUMMARY
==================================================

ก่อนติดตั้งต้องแสดงรายการ Package ที่จะเปลี่ยน:

========================================
         UPDATE SUMMARY
========================================

Packages to Update : 25
Security Updates   : 8
New Packages       : 0
Removed Packages   : 0

Important Packages:

Nginx
PHP-FPM
MariaDB
OpenSSL
systemd
Linux Kernel

========================================

ถาม:

Continue with update? [y/N]

หากมี Package สำคัญ เช่น:

nginx
php
php-fpm
mariadb
openssl
systemd
linux-image

ต้องแสดง WARNING


==================================================
6. INSTALL UPDATE
==================================================

ติดตั้งผ่านระบบ Package Manager ของ Ubuntu

ใช้ APT อย่างถูกต้อง

ไม่ควรใช้:

curl | bash

wget | bash

Script จากแหล่งที่ไม่รู้จัก

ห้ามเพิ่ม Third-party Repository โดยอัตโนมัติ

ห้ามเปลี่ยน Repository โดยไม่ได้รับอนุญาต


==================================================
7. UPDATE PROCESS
==================================================

ระหว่าง Update ต้องแสดง Progress

ตัวอย่าง:

========================================
          SYSTEM UPDATE
========================================

[##########----------] 50%

Updating packages...

Current:
openssl

Next:
nginx

Please wait...

========================================

ห้าม Kill APT Process ระหว่าง Package Installation

ห้ามรัน apt หลายตัวพร้อมกัน


==================================================
8. POST-UPDATE CHECK
==================================================

หลัง Update ต้องตรวจสอบระบบทั้งหมด

ตรวจ:

1. Nginx
2. Nginx Configuration
3. PHP-FPM
4. MariaDB
5. SSL
6. Port 80
7. Port 443
8. Website HTTP Response
9. Website HTTPS Response
10. Disk Space
11. Memory
12. Systemd Services

Nginx:

nginx -t

PHP-FPM:

ตรวจ Service Status

MariaDB:

ตรวจ Service Status

==================================================
9. WEB SERVER HEALTH CHECK
==================================================

หลัง Update ให้ตรวจ Website ทุก Website ที่ระบบจัดการอยู่

ตรวจ:

HTTP Status
HTTPS Status
SSL Certificate
PHP Response
Database Connection

ตัวอย่าง:

========================================
        WEBSITE HEALTH CHECK
========================================

example.com        HTTPS 200   PASS
erp.company.com    HTTPS 200   PASS
shop.company.com   HTTPS 200   PASS

========================================

หาก Website ใดผิดปกติ:

[WARNING] Website health check failed.


==================================================
10. AUTOMATIC ROLLBACK / RECOVERY
==================================================

หาก Update เสร็จแล้วพบว่า:

- Nginx ไม่ทำงาน
- nginx -t FAIL
- PHP-FPM ไม่ทำงาน
- MariaDB ไม่ทำงาน
- Website หลักใช้งานไม่ได้

ให้:

1. แสดง Critical Error
2. ห้ามลบ Backup
3. เก็บ Update Log
4. แนะนำ Recovery
5. หากสามารถ Rollback ได้อย่างปลอดภัย ให้ใช้ Backup Configuration

สำคัญ:

ห้ามทำ Automatic Package Downgrade แบบสุ่ม

ห้าม Force Downgrade Package

ห้ามทำ Recovery ที่อาจทำให้ Database เสียหายโดยอัตโนมัติ

กรณี Database Migration ให้หยุดและแจ้ง Administrator


==================================================
11. KERNEL UPDATE
==================================================

ตรวจสอบว่า Kernel ใหม่ถูกติดตั้งหรือไม่

แสดง:

Current Kernel:
6.x.x

Installed Kernel:
6.x.x

Running Kernel:
6.x.x

หากต้อง Reboot:

Reboot Required: YES

แสดง:

WARNING:
A system reboot is required to activate the new kernel.

ถาม:

1. Reboot Now
2. Reboot Later
0. Cancel

Default:

Reboot Later

ห้าม Reboot โดยอัตโนมัติหลัง Update


==================================================
12. REBOOT REQUIRED STATUS
==================================================

เมนู:

6. Reboot Required Status

ตรวจ:

/var/run/reboot-required

หากมี:

========================================
        REBOOT STATUS
========================================

Reboot Required : YES

Reason:
Kernel update detected.

========================================

ถ้าไม่มี:

Reboot Required : NO


==================================================
13. UPDATE HISTORY
==================================================

เมนู:

4. Update History

แสดง:

Date
Time
User
Ubuntu Version
Kernel
Packages Updated
Security Updates
Result
Reboot Required

ตัวอย่าง:

========================================
          UPDATE HISTORY
========================================

2026-08-14 14:00
User          : admin
Ubuntu        : 24.04
Packages      : 25
Security      : 8
Result        : SUCCESS
Reboot        : YES

========================================


==================================================
14. SYSTEM HEALTH CHECK
==================================================

เมนู:

5. System Health Check

ตรวจ:

========================================
        SYSTEM HEALTH CHECK
========================================

Ubuntu             : PASS
APT                : PASS
Disk Space         : PASS
Memory             : PASS
CPU Load            : PASS
Nginx              : PASS
Nginx Config       : PASS
PHP-FPM             : PASS
MariaDB             : PASS
SSL                : PASS
Port 80             : PASS
Port 443            : PASS
Websites            : PASS

========================================

แสดง:

[ PASS ]
[ WARNING ]
[ CRITICAL ]


==================================================
15. DISK SPACE CHECK
==================================================

ก่อน Update ต้องตรวจพื้นที่:

/
 /var
 /var/log
 /var/lib

หากพื้นที่ต่ำเกินไป:

[WARNING]

หากไม่เพียงพอ:

[CRITICAL]

ห้าม Update


==================================================
16. APT LOCK PROTECTION
==================================================

ก่อนใช้ APT ต้องตรวจว่า Package Manager ถูกใช้งานอยู่หรือไม่

เช่น:

apt
apt-get
dpkg
unattended-upgrades

หากมี Process อื่นกำลังทำงาน:

แสดง:

[WARNING]
Another package manager process is currently running.

ห้ามรัน APT ซ้อนกัน


==================================================
17. UNATTENDED-UPGRADES
==================================================

ตรวจสอบว่า Ubuntu มี:

unattended-upgrades

ทำงานอยู่หรือไม่

หากกำลัง Update:

ห้ามเริ่ม Update ซ้ำ

แสดง:

Automatic update is currently running.

Please wait.


==================================================
18. PACKAGE CONFIGURATION CONFLICT
==================================================

หาก Package Update แจ้ง Configuration Conflict:

ห้ามเลือก:

Force overwrite
หรือ
Force remove

โดยอัตโนมัติ

ให้หยุดและแสดง:

========================================
       CONFIGURATION CONFLICT
========================================

Package:
nginx

Configuration:
...

Action required:
Administrator review

========================================


==================================================
19. UPDATE SAFETY
==================================================

ห้าม:

- apt upgrade แบบ Force
- apt full-upgrade โดยไม่มี Confirmation
- ลบ Package สำคัญโดยอัตโนมัติ
- ลบ nginx
- ลบ PHP-FPM
- ลบ MariaDB
- เปลี่ยน Ubuntu Repository โดยอัตโนมัติ
- เพิ่ม Third-party Repository
- Downgrade Package โดยอัตโนมัติ
- Reboot โดยอัตโนมัติ
- Kill apt/dpkg process
- ใช้ curl | bash
- ใช้ wget | bash


==================================================
20. LOGGING
==================================================

ทุก Update ต้องบันทึก Audit Log:

Date
Time
User
Source IP
Ubuntu Version
Kernel Version
Packages
Action
Result
Error

ตัวอย่าง:

2026-08-14 14:00
admin
192.168.2.10
Ubuntu 24.04
Install Security Updates
SUCCESS


==================================================
21. LOW RESOURCE MODE
==================================================

System Update ต้องใช้ทรัพยากรต่ำ

ห้ามสร้าง:

- Web Server
- Node.js Process
- Database
- Background Daemon

เพิ่มเติมเพื่อจัดการ Update

ใช้:

APT
DPKG
Systemd
Native Linux Commands


==================================================
22. PRODUCTION SAFETY
==================================================

ก่อน Update:

PRE-CHECK
↓
BACKUP
↓
SHOW UPDATE LIST
↓
CONFIRM
↓
INSTALL
↓
POST-CHECK
↓
HEALTH CHECK
↓
REPORT RESULT

หลัง Update ต้องตรวจสอบ Web Server Stack:

Nginx
PHP-FPM
MariaDB

หากระบบใดผิดปกติ:

แสดง WARNING / CRITICAL

และไม่ควรรายงานว่า Update สำเร็จสมบูรณ์จนกว่า Post-Update Health Check จะผ่าน


==================================================
23. FINAL RESULT
==================================================

เมื่อ Update สำเร็จ:

========================================
       UPDATE COMPLETED
========================================

Packages Updated : XX
Security Updates  : XX

Nginx             : OK
PHP-FPM            : OK
MariaDB            : OK
SSL               : OK
Websites           : OK

Reboot Required   : YES/NO

========================================


หากมีปัญหา:

========================================
       UPDATE COMPLETED WITH WARNING
========================================

Update Result : WARNING

Problem:
PHP-FPM service failed after update.

Action Required:
Administrator review.

========================================


==================================================
24. IMPORTANT
==================================================

Menu 12 ต้องทำงานร่วมกับ Menu อื่นที่มีอยู่แล้ว

โดยเฉพาะ:

- Menu 6. Backup
- Menu 7. View Logs
- Menu 8. Security Status
- Menu 9. Server Status
- Menu 11. Fail2Ban
- Menu 13. Nginx

ห้ามสร้างฟังก์ชันซ้ำหากมีฟังก์ชันกลางอยู่แล้ว

ใช้ Shared Function / Utility ของระบบหลักเมื่อสามารถทำได้

ห้ามแก้ไข Menu อื่น
และให้เพิ่มเฉพาะ Menu 12. System Update เท่านั้น
```
