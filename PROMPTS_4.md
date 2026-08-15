
เพิ่ม Web Dashboard สำหรับระบบ CLI Web Server Manager
ที่มีอยู่แล้ว

Dashboard ต้องเป็นส่วนเสริมของระบบเดิม
ไม่ให้กระทบ CLI Manager, Nginx, PHP-FPM, MariaDB,
Fail2Ban, Firewall และระบบ Backup ที่มีอยู่แล้ว

==================================================
1. ARCHITECTURE
==================================================

ใช้ Architecture:

Nginx
   ↓
PHP-FPM
   ↓
Web Dashboard
   ↓
Shared Server Manager Functions
   ↓
Linux Services

Dashboard ต้องใช้:

- PHP
- HTML5
- CSS3
- Vanilla JavaScript

ไม่ใช้:

- Node.js
- React
- Vue
- Angular
- Redis
- PostgreSQL
- MongoDB
- Database เพิ่มสำหรับ Dashboard

เป้าหมาย:

- Lightweight
- Low RAM
- Fast
- Easy to Maintain
- Production Ready

Dashboard ต้องไม่สร้าง Background Daemon เพิ่ม


==================================================
2. DIRECTORY STRUCTURE
==================================================

ติดตั้ง Dashboard แยกจาก CLI:

/opt/serverctl/
    ├── serverctl
    ├── modules/
    ├── config/
    ├── backups/
    ├── logs/
    │
    └── dashboard/
        ├── public/
        │   ├── index.php
        │   ├── login.php
        │   ├── logout.php
        │   ├── assets/
        │   │   ├── css/
        │   │   └── js/
        │   └── api/
        │
        ├── app/
        │   ├── config.php
        │   ├── auth.php
        │   ├── csrf.php
        │   ├── security.php
        │   ├── functions.php
        │   └── services/
        │
        └── views/


==================================================
3. NGINX
==================================================

Dashboard ต้องทำงานผ่าน Nginx + PHP-FPM

ห้ามสร้าง:

PHP built-in server
Node.js server
Python HTTP server

Dashboard ต้องอยู่หลัง:

Nginx
+
PHP-FPM


==================================================
4. DASHBOARD URL
==================================================

กำหนด URL เช่น:

https://server.example.com/manager/

หรือ

https://server.example.com/server-manager/

ไม่ควรเปิด Dashboard ผ่าน HTTP

HTTP:

301 Redirect

HTTPS:

Allowed


==================================================
5. DASHBOARD LOGIN
==================================================

Dashboard ต้องมี Login

หน้า Login:

========================================
       WEB SERVER MANAGER
========================================

Username

[________________________]

Password

[________________________]

[ LOGIN ]

========================================

ห้ามเปิด Dashboard ให้เข้าถึงโดยไม่ Login


==================================================
6. AUTHENTICATION SECURITY
==================================================

ใช้:

PHP Session

Password ต้องเก็บเป็น:

password_hash()

ตรวจด้วย:

password_verify()

ห้ามเก็บ Password แบบ Plain Text

ห้ามเก็บ Password ใน:

JavaScript
HTML
Cookie
Log


==================================================
7. SESSION SECURITY
==================================================

กำหนด:

HttpOnly
Secure
SameSite=Strict

Session ID ต้อง Regenerate หลัง Login:

session_regenerate_id(true)

กำหนด Session Timeout

ตัวอย่าง:

30 นาที

เมื่อไม่มี Activity ให้ Logout อัตโนมัติ


==================================================
8. CSRF PROTECTION
==================================================

ทุก Action ที่เปลี่ยน Server ต้องใช้ CSRF Token

เช่น:

Restart Nginx
Reload Nginx
Stop Nginx
Start Nginx
Update Ubuntu
Backup
Restore
Firewall Change
Fail2Ban Change
Website Change

ห้ามรับ POST Action โดยไม่มี CSRF Validation


==================================================
9. LOGIN RATE LIMIT
==================================================

ป้องกัน Brute Force

กำหนด:

Maximum Login Attempts

เช่น:

5 attempts / 15 minutes

หลังจากเกิน:

Temporary Lock

ต้องบันทึก Audit Log


==================================================
10. DASHBOARD OVERVIEW
==================================================

หน้าแรกต้องเป็น:

========================================
        WEB SERVER MANAGER
========================================

SERVER
----------------------------------------
Hostname       : WEB-SERVER-01
Ubuntu         : 24.04 LTS
Kernel         : 6.x.x
Uptime         : 15 days
CPU            : 18%
RAM            : 42%
Disk           : 56%
Load           : 0.42

SERVICES
----------------------------------------
Nginx          ● RUNNING
PHP-FPM        ● RUNNING
MariaDB        ● RUNNING
Fail2Ban       ● RUNNING
Firewall       ● ENABLED

WEBSITES
----------------------------------------
Websites       : 15
HTTPS          : 15
SSL Expiring   : 2

SECURITY
----------------------------------------
Blocked IPs    : 128
Failed Login   : 24
Fail2Ban Jails : 4

SYSTEM
----------------------------------------
Updates        : 7
Security       : 2
Reboot         : NO

========================================


==================================================
11. STATUS CARDS
==================================================

Dashboard ต้องมี Status Cards:

CPU
RAM
Disk
Load
Nginx
PHP-FPM
MariaDB
Fail2Ban
Firewall
Websites
SSL
Updates


==================================================
12. STATUS COLORS
==================================================

ใช้:

GREEN = OK

YELLOW = WARNING

RED = CRITICAL

GRAY = UNKNOWN

ตัวอย่าง:

Nginx
● RUNNING

MariaDB
● RUNNING

SSL
● EXPIRING SOON

ต้องไม่ใช้สีเพียงอย่างเดียว
ต้องมี Text Status ด้วย


==================================================
13. SERVER MONITOR
==================================================

แสดง:

CPU Usage
RAM Usage
Swap Usage
Disk Usage
Load Average
Uptime
Processes

Dashboard สามารถ Refresh ทุก:

10 - 30 seconds

ไม่ควรใช้ AJAX ทุก 1 วินาที

เป้าหมายคือ Low CPU / Low RAM


==================================================
14. NGINX STATUS
==================================================

แสดง:

Nginx Version
Service Status
Worker Processes
Active Connections
Requests
Port 80
Port 443
HTTP/2
HTTP/3

แสดง:

PASS
WARNING
CRITICAL


==================================================
15. PHP-FPM STATUS
==================================================

แสดง:

PHP Version
PHP-FPM Service
PHP-FPM Socket
Process Count
Memory Usage

หากมีหลาย PHP Version:

PHP 8.2
PHP 8.3
PHP 8.4

ต้องแสดงแยกกัน


==================================================
16. MARIADB STATUS
==================================================

แสดง:

MariaDB Version
Service Status
Uptime
Database Count
Connection Status

ห้ามแสดง:

Database Password
Root Password


==================================================
17. WEBSITE LIST
==================================================

สร้างหน้า:

Websites

แสดง:

Domain
Status
HTTPS
SSL Expiry
PHP Version
Document Root

ตัวอย่าง:

========================================
WEBSITES
========================================

Domain              Status   SSL
----------------------------------------
example.com         ONLINE   OK
shop.example.com    ONLINE   OK
erp.example.com     ONLINE   12 days

========================================


==================================================
18. WEBSITE HEALTH
==================================================

ตรวจ:

HTTP Response
HTTPS Response
Response Time
SSL
PHP
Database

ตัวอย่าง:

example.com

HTTP       : 301
HTTPS      : 200
Response   : 120 ms
SSL        : VALID
PHP        : OK
Database   : OK


==================================================
19. SSL CERTIFICATE
==================================================

แสดง:

Domain
Issuer
Valid From
Expiry Date
Days Remaining

Status:

GREEN:

> 30 days

YELLOW:

≤ 30 days

RED:

≤ 7 days

CRITICAL:

Expired


==================================================
20. SECURITY DASHBOARD
==================================================

สร้างหน้า:

Security

แสดง:

Firewall
Fail2Ban
Blocked IPs
Failed Login Attempts
SSH Status
Open Ports
Security Updates

ตัวอย่าง:

========================================
          SECURITY STATUS
========================================

Firewall        : ENABLED
Fail2Ban        : RUNNING
Blocked IPs     : 128
SSH             : ENABLED
Open Ports      : 3
Security Update : 2

Security Score  : GOOD

========================================


==================================================
21. FIREWALL
==================================================

Dashboard สามารถดู:

Firewall Status
Rules
Allowed Ports
Denied Ports

การเปลี่ยน Firewall ต้อง:

Login
+
CSRF
+
Confirmation
+
Audit Log

ไม่ควรมีปุ่ม:

"Disable Firewall"

บน Dashboard แบบ One Click

ต้องมี Confirmation


==================================================
22. FAIL2BAN
==================================================

แสดง:

Fail2Ban Status
Jails
Banned IPs
Failed Attempts

ตัวอย่าง:

SSH
Banned: 15

Nginx
Banned: 32

สามารถดูรายละเอียดได้

การ Unban IP ต้อง:

Confirmation
+
CSRF
+
Audit Log


==================================================
23. NGINX MANAGEMENT
==================================================

Dashboard สามารถแสดง:

Nginx Status
Configuration Status
Access Log
Error Log

รองรับ Action:

Reload
Restart

แต่ต้อง:

Confirmation
+
CSRF
+
Audit Log

ก่อน Reload/Restart ต้อง:

nginx -t

หาก FAIL:

ห้ามดำเนินการ


==================================================
24. SYSTEM UPDATE
==================================================

Dashboard สามารถแสดง:

Updates Available
Security Updates
Reboot Required

ตัวอย่าง:

Updates Available : 7
Security Updates  : 2
Reboot Required   : NO

สามารถ Link ไป:

System Update

แต่ Update ต้องทำตามระบบของ:

Menu 12. System Update

ห้ามสร้าง Update Logic ซ้ำ


==================================================
25. LOG VIEWER
==================================================

Dashboard ต้องมี:

Nginx Access Log
Nginx Error Log
System Log
Security Log
Audit Log

รองรับ:

Last 50
Last 100
Last 500
Search

ต้องป้องกัน Log Injection / XSS

Log ที่แสดงบน HTML ต้อง Escape Output


==================================================
26. AUDIT LOG
==================================================

ทุก Administrative Action ต้องบันทึก:

Date
Time
User
Source IP
Action
Target
Result

ตัวอย่าง:

2026-08-14 15:20
admin
192.168.2.10
NGINX_RELOAD
SUCCESS


==================================================
27. ACTION CONFIRMATION
==================================================

คำสั่งที่มีความเสี่ยงต้องมี Confirmation

เช่น:

Restart Nginx
Stop Nginx
Start Nginx
Update System
Restore Backup
Delete Website
Delete Database
Firewall Change

ต้องมี Dialog:

========================================

WARNING

This action will affect the production server.

Continue?

[ Cancel ] [ Confirm ]

========================================


==================================================
28. READ-ONLY MODE
==================================================

Dashboard ต้องมี:

Read-only Mode

เมื่อเปิด:

สามารถดู:

Server
Services
Websites
SSL
Security
Logs

แต่ไม่สามารถ:

Restart
Stop
Start
Update
Delete
Restore
Change Firewall

ได้


==================================================
29. ADMINISTRATION MODE
==================================================

เฉพาะ Administrator เท่านั้นที่สามารถ:

Restart Services
Update System
Restore Backup
Delete Website
Delete Database
Change Firewall
Change Security

ต้องตรวจ Permission ทุก Action

ห้ามพึ่งพาเพียงการซ่อนปุ่มด้วย JavaScript


==================================================
30. COMMAND EXECUTION SECURITY
==================================================

ห้ามนำ User Input ต่อ Shell Command โดยตรง

ห้าม:

system($_POST['command']);

exec($_GET['command']);

shell_exec($_REQUEST['cmd']);

ห้ามสร้าง Web Shell

ต้องใช้ Whitelist Command เท่านั้น

ตัวอย่าง:

ALLOW:

systemctl reload nginx

systemctl restart nginx

nginx -t

DENY:

User supplied arbitrary shell command


==================================================
31. ROOT PRIVILEGE
==================================================

Dashboard PHP-FPM ไม่ควรรันเป็น root

ห้าม:

php-fpm → root

Website → root

Dashboard → root

หากจำเป็นต้องทำ Administrative Action
ต้องออกแบบ Privilege Separation อย่างปลอดภัย

เช่น:

sudo whitelist

หรือ

Dedicated privileged helper

โดยอนุญาตเฉพาะคำสั่งที่กำหนดไว้


==================================================
32. SUDO SECURITY
==================================================

หากใช้ sudo:

ต้องใช้ Whitelist

ตัวอย่างแนวคิด:

serverctl nginx status
serverctl nginx reload
serverctl nginx restart

ไม่อนุญาต:

sudo bash
sudo sh
sudo -i
sudo chmod
sudo rm

โดยตรงจาก Web Application


==================================================
33. API
==================================================

Dashboard สามารถใช้ AJAX/API ภายในระบบ

แต่ API ต้อง:

Require Authentication
Require Session
Require CSRF สำหรับ Mutation
Validate Input
Rate Limit
Audit Log

ไม่เปิด API Public โดยไม่มี Authentication


==================================================
34. API RESPONSE
==================================================

API ต้องคืน JSON เช่น:

{
    "status": "success",
    "data": {}
}

ห้ามส่ง:

Password
Secret
Private Key
API Token
Database Credentials


==================================================
35. SECURITY HEADERS
==================================================

Dashboard ต้องใช้:

Strict-Transport-Security
X-Content-Type-Options
X-Frame-Options
Referrer-Policy
Content-Security-Policy
Permissions-Policy

Dashboard ไม่ควรถูกฝังใน iframe:

frame-ancestors 'none'


==================================================
36. COOKIE SECURITY
==================================================

Session Cookie:

Secure
HttpOnly
SameSite=Strict

ห้ามเก็บ Authentication Token ใน:

localStorage

ถ้าไม่จำเป็น


==================================================
37. CONTENT SECURITY
==================================================

ต้องป้องกัน:

XSS
CSRF
SQL Injection
Command Injection
Path Traversal
Session Fixation
Clickjacking
Brute Force

Output ทุกตัวที่มาจาก:

User
Log
Domain
File
System Command

ต้อง Escape ก่อนแสดง HTML


==================================================
38. DATABASE
==================================================

Dashboard ไม่ควรสร้าง Database ใหม่

ถ้าต้องเก็บ:

User
Session
Settings
Audit Log

ให้ใช้ Storage ที่มีอยู่แล้วของระบบ หรือออกแบบ SQLite แบบ Lightweight เฉพาะกรณีจำเป็น

ห้ามเพิ่ม:

MySQL/MariaDB Database ใหม่

เพียงเพื่อ Dashboard


==================================================
39. PERFORMANCE
==================================================

Dashboard ต้อง:

- Lightweight
- Low RAM
- Low CPU
- ไม่มี Background Daemon
- ไม่มี WebSocket ถ้าไม่จำเป็น
- ไม่มี Real-time polling ถี่เกินไป

Default Refresh:

30 seconds

สามารถกด:

Refresh Now


==================================================
40. RESPONSIVE UI
==================================================

รองรับ:

Desktop
Tablet
Mobile

Layout:

Sidebar
Topbar
Content

Desktop:

Sidebar + Dashboard

Mobile:

Collapsible Sidebar


==================================================
41. UI DESIGN
==================================================

ออกแบบให้ดูเหมือน:

Professional Server Control Panel

ไม่ต้องใช้ UI Framework ขนาดใหญ่

ใช้:

HTML5
CSS3
Vanilla JS

ต้องมี:

Status Cards
Tables
Charts แบบ Lightweight
Alerts
Confirmation Dialog


==================================================
42. DASHBOARD MENU
==================================================

Sidebar:

--------------------------------
WEB SERVER MANAGER
--------------------------------

Dashboard

Websites

Nginx

PHP-FPM

MariaDB

SSL Certificates

Security
  ├─ Firewall
  └─ Fail2Ban

Logs

Backup

System Update

Settings

Logout

--------------------------------


==================================================
43. DASHBOARD HOME
==================================================

Dashboard หน้าแรกต้องแสดงภาพรวมทั้งหมด

จัด Layout:

Row 1:

CPU
RAM
Disk
Load

Row 2:

Nginx
PHP-FPM
MariaDB
Fail2Ban

Row 3:

Websites
SSL
Security
Updates

Row 4:

Recent Events
Recent Errors
System Information


==================================================
44. RECENT EVENTS
==================================================

แสดง Event ล่าสุด:

Nginx Reload
Website Added
SSL Renewed
Backup Created
Security Event
System Update

แสดง:

Time
Action
Result


==================================================
45. ALERT SYSTEM
==================================================

Dashboard ต้องมี Alert:

WARNING:

SSL expires in 20 days

Security Update available

Disk usage > 80%

RAM usage > 85%

CRITICAL:

Nginx stopped

MariaDB stopped

SSL expired

Disk usage > 95%

Firewall disabled


==================================================
46. HEALTH SCORE
==================================================

Dashboard สามารถแสดง:

System Health

GOOD
WARNING
CRITICAL

คำนวณจาก:

Nginx
PHP-FPM
MariaDB
Disk
RAM
SSL
Firewall
Fail2Ban
Security Updates

ห้ามใช้ Health Score เพื่อแทนรายละเอียด
ต้องสามารถดูสาเหตุได้


==================================================
47. INSTALLATION
==================================================

Dashboard ต้องติดตั้งผ่าน:

install.sh

ตัวอย่าง:

/tmp/serverctl/install.sh

Installer ต้อง:

1. ตรวจ Ubuntu
2. ตรวจ Nginx
3. ตรวจ PHP-FPM
4. ตรวจ PHP Version
5. ตรวจ Permission
6. สร้าง Dashboard Directory
7. สร้าง Nginx Configuration
8. ตรวจ nginx -t
9. Reload Nginx
10. ตรวจ HTTPS
11. แสดง URL Dashboard


==================================================
48. DASHBOARD CONFIGURATION
==================================================

Configuration แยกจาก Source Code

ตัวอย่าง:

/etc/serverctl/dashboard.conf

ห้ามเก็บ:

Password
API Key
Private Key

ไว้ใน:

public/
JavaScript
HTML


==================================================
49. NGINX CONFIGURATION
==================================================

Dashboard ต้องมี Nginx Configuration แยก:

/etc/nginx/sites-available/serverctl-dashboard.conf

และ:

/etc/nginx/sites-enabled/serverctl-dashboard.conf

ก่อน Enable:

nginx -t

หาก FAIL:

ห้าม Reload


==================================================
50. DASHBOARD ACCESS
==================================================

แนะนำให้รองรับ:

HTTPS Only

และ Optional:

IP Allowlist

เช่น:

Allow:

192.168.2.0/24

Deny:

Public Internet

สำหรับ Management Dashboard

หากเปิด Public Internet ต้องมี:

HTTPS
Authentication
Rate Limit
Security Headers
Audit Log
Fail2Ban


==================================================
51. DEFAULT SECURITY
==================================================

Dashboard Default:

HTTPS
Authentication
CSRF
Session Security
Rate Limit
Security Headers
Audit Log
IP Restriction Optional

ห้าม:

Anonymous Access
Default Password
Hard-coded Password
Hard-coded Secret


==================================================
52. UNINSTALL
==================================================

Dashboard ต้องสามารถ Remove ได้โดยไม่ลบ:

Nginx
PHP-FPM
MariaDB
Websites
SSL
Firewall
Fail2Ban

คำสั่ง:

serverctl dashboard uninstall

ต้องถาม Confirmation ก่อน


==================================================
53. IMPORTANT ARCHITECTURE RULE
==================================================

CLI Manager และ Dashboard ต้องใช้ Shared Logic

ตัวอย่าง:

CLI:

serverctl nginx status

Dashboard:

Nginx Status API

ทั้งสองต้องเรียก Logic เดียวกัน

ไม่เขียน Nginx Detection ซ้ำสองชุด

เช่น:

Shared:

get_nginx_status()
get_php_status()
get_mariadb_status()
get_disk_usage()
get_memory_usage()
get_ssl_status()
get_firewall_status()
get_fail2ban_status()


==================================================
54. FINAL REQUIREMENTS
==================================================

Dashboard ต้อง:

- Production Ready
- Secure by Default
- Lightweight
- Low RAM
- Low CPU
- ใช้ PHP-FPM
- ใช้ Nginx
- ไม่ใช้ Node.js
- ไม่ใช้ React
- ไม่ใช้ Vue
- ไม่ใช้ Database ใหม่โดยไม่จำเป็น
- ไม่สร้าง Background Daemon
- ใช้ CLI Manager Logic เดิม
- มี Authentication
- มี CSRF
- มี Session Security
- มี Rate Limit
- มี Audit Log
- มี Security Headers
- มี HTTPS
- มี Permission Separation
- มี Read-only Mode
- มี Admin Mode
- มี Backup/Restore Integration
- มี Health Check
- มี System Update Integration

ห้ามแก้ไข Menu อื่นของ CLI Manager

ให้เพิ่มเฉพาะ Web Dashboard
และเชื่อมต่อกับระบบเดิมอย่างปลอดภัย
```
