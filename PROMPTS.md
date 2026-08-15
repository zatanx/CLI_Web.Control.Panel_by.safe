สร้างระบบบริหาร Web Server แบบ CLI สำหรับ Ubuntu Server Production โดยมีแนวคิดคล้าย HestiaCP แต่ไม่มี Web Control Panel

เป้าหมายคือ:

* Lightweight
* Secure
* Production Ready
* ใช้ RAM ต่ำ
* ลด Attack Surface
* ไม่เปิด Control Panel Port
* ใช้ SSH เป็นช่องทางบริหาร
* มี Interactive CLI Menu
* สามารถเรียกคำสั่งแบบ CLI ได้
* Website แต่ละตัวแยก Linux User
* รองรับหลาย PHP Version
* รองรับ Let's Encrypt
* รองรับ MariaDB
* รองรับ Firewall
* รองรับ Fail2Ban
* รองรับ AppArmor
* รองรับ Backup
* รองรับ Security Audit

---

# 1. CORE ARCHITECTURE

ใช้:

Ubuntu Server LTS
│
├── UFW / netfilter
├── AppArmor
├── Fail2Ban
│
├── Nginx
│    └── Websites
│
├── PHP-FPM
│    ├── PHP 8.2
│    ├── PHP 8.3
│    └── PHP 8.4
│
├── MariaDB
│
└── Certbot / Let's Encrypt

Management:

SSH
│
└── serverctl
│
├── Interactive Menu
└── CLI Commands

ไม่มี Web Control Panel

ไม่มี Node.js Service

ไม่มี Apache

ไม่มี Mail Server

ไม่มี BIND

ไม่มี ClamAV

ไม่มี SpamAssassin

ไม่มี FTP Server

ถ้าไม่จำเป็น

---

# 2. SECURITY ARCHITECTURE

ใช้ Defense in Depth:

FortiGate / External Firewall
↓
Ubuntu Firewall
↓
AppArmor
↓
Nginx
↓
PHP-FPM
↓
Website User Isolation
↓
Application
↓
MariaDB

Administration:

SSH Key
↓
serverctl
↓
Validated Action
↓
Restricted sudo
↓
Specific System Command

ห้าม Web Application

ห้าม Arbitrary Shell Command

---

# 3. TARGET OS

รองรับ:

Ubuntu Server 24.04 LTS
Ubuntu Server 22.04 LTS

Installer ต้องตรวจสอบ:

* OS
* Version
* Architecture
* RAM
* Disk
* CPU
* Internet
* Root Privilege

หากไม่ตรง Requirement ให้หยุดติดตั้ง

---

# 4. MAIN SOFTWARE

ติดตั้งเฉพาะ:

* Nginx
* PHP-FPM
* MariaDB
* Certbot
* UFW
* Fail2Ban
* AppArmor
* unattended-upgrades
* logrotate

Optional:

* Lynis
* rkhunter

ไม่ติดตั้ง:

* Apache
* Exim
* Dovecot
* BIND
* ClamAV
* SpamAssassin
* PostgreSQL
* FTP Server

---

# 5. INSTALLER

สร้าง:

install.sh

ใช้งาน:

sudo bash install.sh

Installer ต้อง:

1. ตรวจ Root
2. ตรวจ Ubuntu
3. ตรวจ RAM
4. ตรวจ Disk
5. ตรวจ Internet
6. Update apt
7. ติดตั้ง Nginx
8. ติดตั้ง PHP-FPM
9. ติดตั้ง PHP Extensions
10. ติดตั้ง MariaDB
11. Secure MariaDB
12. ติดตั้ง Certbot
13. ติดตั้ง UFW
14. ติดตั้ง Fail2Ban
15. ตรวจ AppArmor
16. ติดตั้ง unattended-upgrades
17. ตั้ง logrotate
18. สร้าง serverctl
19. สร้าง Directory Structure
20. ตั้ง Permission
21. ตั้ง sudo policy
22. Enable Services
23. Run Security Check
24. Run Health Check
25. แสดง Installation Summary

Log:

/var/log/serverctl/install.log

---

# 6. DIRECTORY STRUCTURE

ใช้:

/opt/serverctl/

/etc/serverctl/

/var/lib/serverctl/

/var/log/serverctl/

/var/backups/serverctl/

/var/www/

ตัวอย่าง:

/opt/serverctl/
bin/
lib/
modules/
config/

/etc/serverctl/
serverctl.conf
php/
nginx/
security/

/var/lib/serverctl/
database/

/var/log/serverctl/

/var/backups/serverctl/

---

# 7. MAIN COMMAND

สร้าง:

/usr/local/bin/serverctl

ต้องสามารถรัน:

sudo serverctl

เพื่อเปิด Interactive Menu

---

# 8. CLI MENU

หน้าหลัก:

========================================
WEB SERVER MANAGER
==================

Server : web-server-01
OS     : Ubuntu 24.04 LTS
IP     : 192.168.2.20

---

1. Add Website

2. Remove Website

3. Enable SSL

4. Create Database

5. PHP Version

6. Backup

7. View Logs

8. Security Status

9. Server Status

10. Firewall

11. Fail2Ban

12. System Update

13. Exit

========================================

Select option:

Menu ต้อง:

* อ่านง่าย
* รองรับสี Terminal ถ้า Terminal รองรับ
* มี Confirmation
* มี Error Handling
* ไม่ทำ Dangerous Action โดยไม่ถาม

---

# 9. NON-INTERACTIVE CLI

นอกจาก Menu ต้องรองรับ CLI Command

ตัวอย่าง:

serverctl status

serverctl security status

serverctl website list

serverctl website add example.com --php 8.3

serverctl website remove example.com

serverctl ssl enable example.com

serverctl ssl status

serverctl database list

serverctl database create erp

serverctl database remove erp

serverctl php list

serverctl php set example.com 8.3

serverctl backup create

serverctl backup list

serverctl backup restore

serverctl logs nginx

serverctl logs php

serverctl firewall status

serverctl fail2ban status

serverctl update check

---

# 10. WEBSITE MANAGEMENT

คำสั่ง:

serverctl website list

แสดง:

Domain
PHP Version
Status
SSL
Document Root
User

ตัวอย่าง:

example.com
PHP 8.3
SSL YES
ONLINE

---

# 11. ADD WEBSITE

คำสั่ง:

serverctl website add example.com --php 8.3

ต้อง:

1. Validate Domain
2. ตรวจ Duplicate
3. สร้าง Linux User
4. สร้าง Website Directory
5. สร้าง Public Directory
6. ตั้ง Permission
7. สร้าง PHP-FPM Pool
8. สร้าง Nginx Config
9. Validate Nginx
10. Reload Nginx
11. บันทึกข้อมูล
12. Health Check

Directory:

/var/www/example.com/public

---

# 12. WEBSITE USER ISOLATION

แต่ละ Website ต้องมี User แยก

ตัวอย่าง:

example.com
→ web-example

erp.company.com
→ web-erp

PHP-FPM Pool:

user = web-example
group = web-example

ห้าม Website A อ่าน:

/var/www/website-b

ห้าม chmod 777

---

# 13. PHP-FPM POOL

แต่ละ Website มี Pool

ตัวอย่าง:

/etc/php/8.3/fpm/pool.d/example.com.conf

ต้องกำหนด:

user
group
listen
pm
pm.max_children
pm.max_requests
request_terminate_timeout

ใช้ Unix Socket

ตัวอย่าง:

/run/php/serverctl/example.sock

---

# 14. MULTIPLE PHP VERSION

รองรับ:

PHP 8.2
PHP 8.3
PHP 8.4

ไม่จำเป็นต้องติดตั้งทุก Version

คำสั่ง:

serverctl php list

แสดง:

PHP 8.2
PHP 8.3 *
PHP 8.4

เปลี่ยน Version:

serverctl php set example.com 8.4

ต้อง:

1. Validate Version
2. ตรวจ Package
3. Backup Config
4. Update FPM Pool
5. Validate PHP-FPM
6. Reload PHP-FPM
7. Test Website

---

# 15. PHP EXTENSIONS

Default:

pdo
pdo_mysql
mysqli
mbstring
curl
zip
gd
xml
intl
bcmath
opcache

Optional:

redis
imagick

ไม่ติดตั้ง Extension ทั้งหมดโดยไม่จำเป็น

---

# 16. PHP SECURITY

Production Defaults:

display_errors = Off
log_errors = On
expose_php = Off
allow_url_include = Off
session.cookie_httponly = On
session.cookie_secure = On
session.use_strict_mode = On

ต้องรองรับ Website-specific PHP Configuration

---

# 17. NGINX

สร้าง:

/etc/nginx/sites-available/example.com.conf

Link:

/etc/nginx/sites-enabled/example.com.conf

Config ต้อง:

* HTTPS
* HTTP Redirect
* PHP-FPM
* Security Headers
* Block Hidden Files
* Block Sensitive Files
* Client Max Body Size
* Access Log
* Error Log

ก่อน Reload:

nginx -t

ถ้า Fail:

ห้าม Reload

---

# 18. NGINX SECURITY

Block:

.env
.git
.gitignore
*.sql
*.log
config.php
composer.json
composer.lock

Block:

location ~ /. {
deny all;
}

ห้ามเปิด Directory Listing

ห้าม Execute PHP ใน Upload Directory

---

# 19. SECURITY HEADERS

รองรับ:

X-Content-Type-Options
X-Frame-Options
Referrer-Policy
Permissions-Policy
Content-Security-Policy
Strict-Transport-Security

CSP ต้องสามารถกำหนดต่อ Website

ไม่เปิด HSTS Preload โดยอัตโนมัติ

---

# 20. SSL

ใช้:

Certbot
Let's Encrypt

คำสั่ง:

serverctl ssl enable example.com

ต้อง:

1. ตรวจ Domain
2. ตรวจ DNS
3. ตรวจ Port 80
4. Request Certificate
5. Configure Nginx
6. Test Nginx
7. Reload Nginx
8. Enable HTTPS

---

# 21. SSL RENEWAL

ใช้:

systemd timer

หรือ cron

ต้องตรวจ:

Expire Date

แจ้ง:

30 วัน
14 วัน
7 วัน
3 วัน

---

# 22. MARIADB

ติดตั้ง MariaDB

Secure:

* Remove anonymous users
* Remove test database
* Disable remote root
* Strong Authentication

Default:

bind-address = 127.0.0.1

ถ้าไม่ต้องการ Remote Database

---

# 23. DATABASE MANAGEMENT

คำสั่ง:

serverctl database list

serverctl database create erp

serverctl database remove erp

ต้องสามารถ:

Create Database
Create User
Set Password
Grant Permission
Backup
Restore

Database User ต้องเข้าถึงเฉพาะ Database ของตัวเอง

---

# 24. FIREWALL

ใช้ UFW

Default:

Incoming DENY
Outgoing ALLOW

เปิด:

22 SSH
80 HTTP
443 HTTPS

3306:

DENY WAN

ไม่มี Control Panel Port 8083

---

# 25. FIREWALL MENU

Menu:

10. Firewall

แสดง:

========================================
FIREWALL
========

22     SSH       ALLOW
80     HTTP      ALLOW
443    HTTPS     ALLOW
3306   MariaDB   DENY

1. Add Rule

2. Remove Rule

3. List Rules

4. Reload Firewall

5. Back

ทุก Rule ต้อง Validate

ห้ามเปิด:

0.0.0.0/0

โดยไม่มี Warning และ Confirmation

---

# 26. FAIL2BAN

ติดตั้ง Fail2Ban

Jails:

sshd
nginx-http-auth
nginx-limit-req

Optional:

serverctl-login

แสดง:

Status
Banned IP
Attempts
Ban Time

คำสั่ง:

serverctl fail2ban status

serverctl fail2ban list

serverctl fail2ban ban IP

serverctl fail2ban unban IP

---

# 27. APPARMOR

ต้องเปิด AppArmor

ตรวจ:

aa-status

ห้าม Installer ปิด AppArmor

ถ้ามี Profile:

Enforce

ต้องมี Security Status:

AppArmor = ENABLED

---

# 28. SSH SECURITY

Default:

PermitRootLogin no

PasswordAuthentication:

สามารถปิดได้เมื่อ SSH Key พร้อม

Installer ต้องตรวจสอบ SSH Key ก่อน

ห้ามทำให้ Admin Lockout ตัวเอง

Fail2Ban:

sshd

---

# 29. CONTROL PANEL SECURITY

ไม่มี Web Control Panel

ไม่มี Port:

8083

ไม่มี HTTP Administration Interface

Administration ผ่าน:

SSH

และ:

serverctl

---

# 30. SERVER STATUS

Menu:

9. Server Status

แสดง:

CPU
RAM
Disk
Load
Uptime
Network

Services:

Nginx
PHP-FPM
MariaDB
Fail2Ban
UFW
AppArmor

ตัวอย่าง:

CPU        12%
RAM        2.1 / 8 GB
Disk       180 / 500 GB
Load       0.42
Uptime     32 days

Nginx      RUNNING
PHP-FPM    RUNNING
MariaDB    RUNNING
Fail2Ban   RUNNING
UFW        ACTIVE
AppArmor   ENABLED

---

# 31. SECURITY STATUS

Menu:

8. Security Status

แสดง:

Firewall
Fail2Ban
AppArmor
SSH
MariaDB
SSL
Updates
Permissions
Open Ports
Backup

ตัวอย่าง:

========================================
SECURITY STATUS
===============

Firewall        [ OK ]
Fail2Ban        [ OK ]
AppArmor        [ OK ]
SSH Root Login  [ OK ]
MariaDB Remote  [ OK ]
3306 Public     [ OK ]
SSL             [ OK ]
Updates         [ OK ]
Permissions     [ OK ]
Backup          [ OK ]

Security Score: 94 / 100

========================================

---

# 32. SECURITY SCANNER

ตรวจ:

* Root Login
* SSH Password Authentication
* Firewall
* Fail2Ban
* AppArmor
* Open Ports
* MariaDB Remote
* 3306 Public
* SSL
* Security Updates
* World Writable Files
* 777 Permissions
* Suspicious SUID
* Outdated Packages
* Unexpected Services

สถานะ:

PASS
WARNING
CRITICAL

---

# 33. OPEN PORT SCANNER

ใช้:

ss -tulpn

แสดง:

Port
Protocol
Process
PID
Address

ถ้าพบ Port ที่ไม่อยู่ใน Allowlist:

WARNING

---

# 34. FILE PERMISSION SCANNER

ตรวจ:

/var/www/

ค้นหา:

777
666
World Writable
Unexpected Owner
Unexpected Group

ห้ามแก้ไขอัตโนมัติโดย Default

---

# 35. SUSPICIOUS PHP SCANNER

ค้นหา:

eval(
base64_decode(
shell_exec(
system(
passthru(
assert(

แสดง:

SUSPICIOUS

ไม่ลบอัตโนมัติ

เพราะอาจเกิด False Positive

---

# 36. LYNIS

Optional:

Lynis

คำสั่ง:

serverctl security audit

แสดง:

Security Score
Warnings
Suggestions

---

# 37. SYSTEM UPDATE

Menu:

12. System Update

คำสั่ง:

serverctl update check

serverctl update security

serverctl update all

ต้องแสดง:

Security Updates
Normal Updates
Kernel Update
Reboot Required

ห้าม Major OS Upgrade อัตโนมัติ

---

# 38. AUTOMATIC SECURITY UPDATE

ติดตั้ง:

unattended-upgrades

เปิด Security Updates

ต้อง:

* Log
* Show Last Update
* Show Pending Update
* Show Reboot Required

---

# 39. BACKUP

Menu:

6. Backup

แสดง:

1. Backup Website
2. Backup Database
3. Backup Everything
4. List Backups
5. Restore
6. Delete Backup
7. Verify Backup

Backup:

Website Files
Database
Nginx Config
PHP-FPM Config
Serverctl Config
Firewall Config
Fail2Ban Config

---

# 40. BACKUP LOCATION

Primary:

/var/backups/serverctl/

แต่ต้องรองรับ Remote Backup:

* NAS
* SMB
* NFS
* SFTP
* rsync

Backup ไม่ควรเก็บอยู่บน Server เดียวเท่านั้น

---

# 41. BACKUP ENCRYPTION

Sensitive Backup ต้องรองรับ Encryption

ใช้:

AES-256

Encryption Key ห้ามเก็บ:

* Web Root
* Git
* Database

---

# 42. BACKUP RETENTION

รองรับ:

7 days
14 days
30 days
90 days

กำหนดได้ใน:

/etc/serverctl/serverctl.conf

---

# 43. BACKUP VERIFICATION

ต้องมี:

serverctl backup verify

ตรวจ:

* File Integrity
* Archive Integrity
* Database Backup Integrity

และต้องรองรับ:

Restore Test

---

# 44. LOG MANAGEMENT

Menu:

7. View Logs

ตัวเลือก:

1. Nginx Access
2. Nginx Error
3. PHP-FPM
4. MariaDB
5. Fail2Ban
6. Firewall
7. System
8. Serverctl

ต้องรองรับ:

Last 50
Last 100
Last 500
Live
Search

---

# 45. LOGROTATE

ใช้ logrotate

ต้องจัดการ:

Nginx
PHP-FPM
MariaDB
Fail2Ban
Serverctl

Retention:

30 days

Compress:

gzip

---

# 46. AUDIT LOG

บันทึก:

Login
Website Add
Website Remove
SSL Enable
Database Create
Database Remove
PHP Change
Backup
Restore
Firewall Change
Fail2Ban Ban
Fail2Ban Unban
System Update
Security Change

เก็บ:

Time
User
IP
Action
Result

---

# 47. COMMAND AUDIT

ทุก serverctl command ต้อง Log

ตัวอย่าง:

2026-08-14
admin
192.168.2.10
website add example.com
SUCCESS

ห้ามเก็บ:

Password
Private Key
API Token

ใน Audit Log

---

# 48. CONFIGURATION ROLLBACK

ก่อนแก้:

Nginx
PHP-FPM
Firewall
SSH
Fail2Ban

ต้อง Backup Config

Flow:

Backup
↓
Generate
↓
Validate
↓
Apply
↓
Health Check
↓
Success

ถ้า Error:

Rollback

---

# 49. WEBSITE REMOVE SAFETY

ก่อน Delete:

แสดง:

Domain
User
Files
Database
SSL

ถาม:

Backup before delete?

และต้องยืนยัน Domain:

Type:

example.com

เพื่อยืนยัน

---

# 50. DATABASE REMOVE SAFETY

ต้อง:

Confirmation

และมี:

Backup Database

ก่อน Delete

---

# 51. FILE PERMISSION

Default:

Directory = 755

File = 644

Sensitive = 600 / 640

ห้าม:

chmod 777

---

# 52. SECRET MANAGEMENT

ห้าม Hard-code:

Database Password
API Token
Encryption Key
Private Key

Sensitive Config:

Permission 600

---

# 53. SYSTEM COMMAND SECURITY

ทุกคำสั่งต้องผ่าน:

Command Service

ห้าม:

shell_exec(UserInput)

exec(UserInput)

system(UserInput)

passthru(UserInput)

Commands ต้อง Whitelist

Parameters ต้อง Validate

---

# 54. PATH SECURITY

Website Root ต้องอยู่:

/var/www/

ห้าม:

/etc
/root
/boot
/proc
/sys
/var/lib/mysql

---

# 55. SERVICE SECURITY

ต้องมี:

systemd

Enable:

nginx
php-fpm
mariadb
fail2ban

UFW:

enabled

AppArmor:

enabled

---

# 56. HEALTH CHECK

คำสั่ง:

serverctl health

ตรวจ:

Nginx
PHP-FPM
MariaDB
SSL
Firewall
Fail2Ban
AppArmor
Disk
RAM
CPU

Return:

OK
WARNING
CRITICAL

---

# 57. DOMAIN HEALTH CHECK

ตรวจ:

DNS
HTTP
HTTPS
SSL
Nginx
PHP

ตัวอย่าง:

serverctl website health example.com

---

# 58. SSL HEALTH CHECK

ตรวจ:

Certificate
Issuer
Expiry
Chain
HTTPS
HTTP Redirect

---

# 59. PHP HEALTH CHECK

ตรวจ:

PHP Version
PHP-FPM
Pool
Socket
OPcache
Memory Limit

---

# 60. DATABASE HEALTH CHECK

ตรวจ:

MariaDB Status
Connections
Database Size
Disk
Slow Queries

ห้ามแสดง Database Password

---

# 61. RESOURCE MONITORING

แสดง:

CPU
RAM
Disk
Load
Network

ต้องสามารถ:

serverctl status

และ:

serverctl status --watch

---

# 62. CONFIGURATION FILE

สร้าง:

/etc/serverctl/serverctl.conf

กำหนด:

DEFAULT_PHP_VERSION=8.3

BACKUP_RETENTION=30

BACKUP_PATH=/var/backups/serverctl

WEB_ROOT=/var/www

PANEL_PORT=none

SSH_PORT=22

TIMEZONE=Asia/Bangkok

---

# 63. TIMEZONE

Default:

Asia/Bangkok

แต่สามารถเปลี่ยนได้

เวลาที่แสดงใน Audit Log และ Backup ต้องใช้ Server Timezone

---

# 64. ERROR HANDLING

ทุกคำสั่งต้อง:

* Validate
* Execute
* Check Exit Code
* Capture Error
* Log
* Rollback ถ้าทำได้

ไม่แสดง Sensitive Information

---

# 65. USER EXPERIENCE

Menu ต้อง:

* ใช้ง่าย
* อ่านง่าย
* มีสี
* ใช้ Unicode ได้ถ้า Terminal รองรับ
* มี fallback สำหรับ Terminal ที่ไม่รองรับสี

ตัวอย่าง:

[ OK ]
[ WARNING ]
[ ERROR ]

---

# 66. NON-INTERACTIVE MODE

ทุกคำสั่งต้องสามารถใช้ Script/Automation ได้

ตัวอย่าง:

serverctl website add example.com --php 8.3 --yes

serverctl ssl enable example.com --yes

serverctl backup create --all

Exit Code:

0 = Success

1 = General Error

2 = Invalid Argument

3 = Permission Error

4 = Validation Error

5 = System Error

---

# 67. CRON / SYSTEMD TIMER

ใช้สำหรับ:

SSL Renewal
Backup
Security Scan
Log Cleanup
Update Check

ไม่ควรใช้ Background Daemon ถ้าไม่จำเป็น

---

# 68. SECURITY ALERT

แจ้งเตือนเมื่อ:

Failed SSH Login
IP Banned
SSL Expiring
Disk > 80%
Disk > 90%
Service Down
Firewall Disabled
Fail2Ban Disabled
AppArmor Disabled
Security Update Available
Reboot Required

สามารถรองรับ:

Telegram

Email

แต่เป็น Optional

---

# 69. TELEGRAM ALERT

ถ้าเปิดใช้งาน:

แจ้ง:

Server Down
Service Down
Security Alert
Backup Failed
SSL Expiring
Disk Critical
IP Banned

Token และ Chat ID ต้องเก็บใน Protected Config

ห้ามแสดง Token ใน Terminal

---

# 70. SERVER SECURITY SCORE

คำนวณ:

Firewall 20
AppArmor 15
SSH 15
Fail2Ban 10
PHP 10
MariaDB 10
SSL 10
Updates 5
Permissions 5

รวม:

100

แสดง:

90-100 Excellent
75-89 Good
60-74 Warning
<60 Critical

---

# 71. INSTALLATION PROFILES

รองรับ:

Minimal
Standard
Custom

Minimal:

Nginx
PHP-FPM
MariaDB
Certbot
UFW
Fail2Ban
AppArmor

Standard:

Minimal
+
Multiple PHP Versions
+
Lynis
+
Backup Tools

Custom:

ให้เลือก Component

---

# 72. NO WEB UI

Project นี้ห้ามมี:

Web Control Panel
Dashboard Web
Port 8083
HTTP Admin Interface
Node.js Admin Server

การบริหารทั้งหมดผ่าน:

SSH
serverctl

---

# 73. SSH HARDENING

แนะนำ:

SSH Key

สามารถ:

serverctl security ssh

แสดง:

Root Login
Password Login
SSH Port
Allowed Users

และสามารถ Harden:

PermitRootLogin no

PasswordAuthentication no

แต่ต้องตรวจสอบ Key ก่อน

---

# 74. PRODUCTION SECURITY

Default ต้อง:

Firewall Enabled
Fail2Ban Enabled
AppArmor Enabled
MariaDB Localhost
Root SSH Disabled
3306 Blocked WAN
Website Isolation
PHP-FPM Pool Isolation
Security Updates Enabled
HTTPS
Secure Permissions

---

# 75. DOCUMENTATION

สร้าง:

README.md
INSTALL.md
SECURITY.md
BACKUP.md
UPDATE.md
TROUBLESHOOTING.md
CLI.md
ARCHITECTURE.md

CLI.md ต้องมีทุก Command พร้อมตัวอย่าง

---

# 76. TESTING

ต้องมี Test:

Installer Test
Website Test
SSL Test
Database Test
PHP Test
Firewall Test
Fail2Ban Test
AppArmor Test
Backup Test
Restore Test
Security Test

---

# 77. SECURITY TEST

ทดสอบ:

SQL Injection
Command Injection
Path Traversal
Privilege Escalation
Permission Bypass
Unauthorized Website Access
Database Access
SSH Brute Force
Nginx Misconfiguration

---

# 78. ACCEPTANCE TEST

หลังติดตั้งต้องสามารถ:

[ ] เปิด serverctl

[ ] Add Website

[ ] Remove Website

[ ] เปลี่ยน PHP Version

[ ] Create Database

[ ] Enable SSL

[ ] Auto Renew SSL

[ ] Backup Website

[ ] Backup Database

[ ] Restore Backup

[ ] View Logs

[ ] View Security Status

[ ] View Server Status

[ ] Manage Firewall

[ ] Manage Fail2Ban

[ ] Check System Update

[ ] Security Scan

[ ] Health Check

---

# 79. FINAL ARCHITECTURE

Final Server:

```
                INTERNET
                   │
              FORTIGATE
                   │
              UBUNTU LTS
                   │
         ┌─────────┴─────────┐
         │                   │
        UFW               AppArmor
         │                   │
         └─────────┬─────────┘
                   │
                NGINX
                   │
               PHP-FPM
                   │
         ┌─────────┼─────────┐
         │         │         │
      Website A Website B Website C
         │         │         │
      User A    User B    User C
         │         │         │
         └─────────┼─────────┘
                   │
                MariaDB
```

Administration:

ADMIN
│
VPN / LAN
│
SSH Key
│
serverctl
│
Validated Commands
│
Restricted sudo
│
System

---

# 80. FINAL OBJECTIVE

สร้างระบบที่มีความสามารถใกล้เคียง Hosting Control Panel แต่ไม่มี Web Control Panel

ต้องได้:

* Lightweight
* Low RAM
* Secure
* Easy CLI Management
* Production Ready
* Multi Website
* Multi PHP
* MariaDB
* SSL
* Backup
* Firewall
* Fail2Ban
* AppArmor
* Security Audit
* Health Monitoring

หลักการสำคัญ:

"ถ้าไม่จำเป็น อย่าติดตั้ง"

"ถ้าไม่จำเป็น อย่าเปิด Port"

"ถ้าไม่จำเป็น อย่าให้สิทธิ์ Root"

"ทุก Configuration Change ต้อง Validate"

"ทุก Dangerous Action ต้อง Confirm"

"ทุก Security Action ต้อง Audit"

"ทุก Backup ต้องสามารถตรวจสอบและ Restore ได้"

"Web Application ต้องไม่สามารถกลายเป็น Root Shell"

เป้าหมายคือสร้าง CLI Web Server Manager ที่เรียบง่ายกว่า HestiaCP แต่ให้ความสามารถด้าน Web Hosting ที่จำเป็นสำหรับ Production และมี Attack Surface ต่ำที่สุดเท่าที่ทำได้
