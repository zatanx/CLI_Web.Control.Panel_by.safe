เพิ่มเมนู: Nginx

เมื่อลูกค้าเลือกเมนู 13 ให้แสดงเมนูดังนี้:

========================================
              NGINX
========================================

Status      : RUNNING
Version     : 1.xx.x
Config      : VALID

----------------------------------------

  1. Nginx Status
  2. Test Configuration
  3. Reload Nginx
  4. Restart Nginx
  5. Stop Nginx
  6. Start Nginx
  7. View Configuration
  8. Global Settings
  9. Website Configuration
 10. Security Settings
 11. Access Log
 12. Error Log
 13. Backup Configuration
 14. Restore Configuration
 15. Configuration History

  0. Back

========================================
Select option:


==================================================
1. NGINX STATUS
==================================================

แสดง:

- Nginx Service Status
- Nginx Version
- PID
- Worker Processes
- Active Connections
- Uptime
- Configuration Status
- HTTP Status
- HTTPS Status
- HTTP/2 Status
- HTTP/3 Status

ใช้คำสั่งที่เหมาะสม เช่น:

systemctl is-active nginx
nginx -v
nginx -t

==================================================
2. TEST CONFIGURATION
==================================================

ใช้:

nginx -t

ถ้า PASS:

[ OK ] Nginx configuration is valid.

ถ้า FAIL:

[ ERROR ] Nginx configuration is invalid.

ต้องแสดง Error ที่เกี่ยวข้อง

หาก nginx -t ไม่ผ่าน:

- ห้าม Reload
- ห้าม Restart
- ห้าม Apply Configuration
- ต้องรักษา Configuration เดิมที่กำลังใช้งานอยู่

==================================================
3. RELOAD NGINX
==================================================

ก่อน Reload:

1. Backup Configuration
2. nginx -t
3. หาก PASS ให้ Reload
4. ตรวจ Service Status
5. Health Check

ใช้:

systemctl reload nginx

ห้าม Reload หาก nginx -t ไม่ผ่าน

==================================================
4. RESTART NGINX
==================================================

ก่อน Restart:

nginx -t

หาก FAIL:

ห้าม Restart

หาก PASS ให้ถาม:

WARNING:
Restarting Nginx may temporarily interrupt connections.

Continue? [y/N]

หลัง Restart ต้องตรวจ:

- Service Status
- Configuration
- Port 80
- Port 443
- Health Check

==================================================
5. STOP NGINX
==================================================

แสดง:

WARNING:
Stopping Nginx will make all websites unavailable.

Continue? [y/N]

ต้องมี Confirmation ก่อน Stop

ใช้:

systemctl stop nginx

==================================================
6. START NGINX
==================================================

ก่อน Start:

nginx -t

หาก PASS:

systemctl start nginx

หลัง Start ต้องตรวจ:

- Service Status
- Port 80
- Port 443
- Health Check

==================================================
7. VIEW CONFIGURATION
==================================================

แสดง:

1. Main Configuration
2. Sites Available
3. Sites Enabled
4. Snippets
5. Included Configuration

Main Configuration:

/etc/nginx/nginx.conf

Sites:

/etc/nginx/sites-available/
/etc/nginx/sites-enabled/

Snippets:

/etc/nginx/snippets/

เมนูนี้เป็น View Only
ห้ามแก้ Configuration จากเมนูนี้

==================================================
8. GLOBAL SETTINGS
==================================================

แสดง:

========================================
        NGINX GLOBAL SETTINGS
========================================

  1. Worker Processes
  2. Worker Connections
  3. Keepalive Timeout
  4. Client Max Body Size
  5. Gzip
  6. Brotli
  7. HTTP/2
  8. HTTP/3
  9. Access Log
 10. Error Log
 11. Security Headers
 12. Request Timeout
 13. Custom Configuration

  0. Back

========================================

ทุกการเปลี่ยนแปลงต้อง:

Backup
→ Modify
→ nginx -t
→ Show Diff
→ Confirm
→ Apply
→ Health Check

หาก nginx -t FAIL:

ห้าม Apply

==================================================
9. WEBSITE CONFIGURATION
==================================================

ใช้ Website ที่มีอยู่แล้วในระบบหลัก

แสดง:

========================================
       NGINX WEBSITE CONFIG
========================================

  1. example.com
  2. erp.company.com
  3. shop.company.com

  0. Back

========================================

เมื่อเลือก Website:

========================================
       example.com - NGINX
========================================

  1. View Config
  2. Edit Config
  3. Force HTTPS
  4. Security Headers
  5. Upload Limit
  6. Access Rules
  7. Rate Limit
  8. Static Cache
  9. Custom Rules
 10. Test Config

  0. Back

========================================

ทุก Configuration Change ต้อง:

Backup
→ Modify
→ nginx -t
→ Show Diff
→ Confirm
→ Apply
→ Health Check

==================================================
10. SECURITY SETTINGS
==================================================

แสดง:

========================================
        NGINX SECURITY SETTINGS
========================================

  1. Hide Nginx Version
  2. Block Hidden Files
  3. Block Sensitive Files
  4. Disable Directory Listing
  5. Block PHP in Uploads
  6. Security Headers
  7. Default Server
  8. Request Limits
  9. Security Audit

  0. Back

========================================

Default Security:

server_tokens off;

Directory Listing:

autoindex off;

Block Hidden Files:

.git
.env
.htaccess
.htpasswd

ยกเว้น:

.well-known

Block PHP Execution ใน Upload Directory

Default Server ต้องไม่เปิดเผยข้อมูล Nginx

==================================================
11. ACCESS LOG
==================================================

แสดง:

  1. Last 50
  2. Last 100
  3. Last 500
  4. Live
  5. Search

รองรับ:

- Global Access Log
- Website Access Log

==================================================
12. ERROR LOG
==================================================

แสดง:

  1. Last 50
  2. Last 100
  3. Last 500
  4. Live
  5. Search

รองรับ:

- Global Error Log
- Website Error Log

==================================================
13. BACKUP CONFIGURATION
==================================================

Backup Nginx Configuration:

/etc/nginx/nginx.conf
/etc/nginx/sites-available/
/etc/nginx/sites-enabled/
/etc/nginx/snippets/
/etc/nginx/conf.d/

เก็บ Backup ไว้ที่:

/var/backups/serverctl/nginx/

ตั้งชื่อ Backup เช่น:

2026-08-14_140000/

ก่อนแก้ Nginx Configuration ทุกครั้งต้อง Backup

==================================================
14. RESTORE CONFIGURATION
==================================================

แสดงรายการ Backup:

========================================
       NGINX CONFIG BACKUP
========================================

  1. 2026-08-14 14:00
  2. 2026-08-14 12:30
  3. 2026-08-13 09:15

  0. Back

========================================

เมื่อเลือก Backup:

Backup Current Configuration
        ↓
Restore Selected Backup
        ↓
nginx -t
        ↓
Reload
        ↓
Health Check

หาก nginx -t FAIL:

ยกเลิกการ Restore
และรักษา Configuration ปัจจุบัน

==================================================
15. CONFIGURATION HISTORY
==================================================

บันทึก:

Date
Time
User
Source IP
Action
Result

ตัวอย่าง:

2026-08-14 14:00
admin
192.168.2.10
Change Nginx Configuration
SUCCESS

==================================================
IMPORTANT SAFETY RULES
==================================================

ทุกครั้งที่แก้ไข Nginx Configuration ต้องใช้:

BACKUP
↓
VALIDATE
↓
SHOW DIFF
↓
CONFIRM
↓
APPLY
↓
HEALTH CHECK

ห้าม:

- Reload Configuration ที่ nginx -t ไม่ผ่าน
- Restart Nginx โดยไม่ Test Configuration
- ลบ Configuration เดิมก่อน Backup
- ใช้ chmod 777
- ให้ Website User เป็น root
- เปิด Nginx Management UI
- เปิด Management Port เพิ่ม
- เปิด Nginx Status ให้ Public Internet
- Bypass nginx -t
- ใช้ --force เพื่อข้าม Security Validation

==================================================
DESIGN REQUIREMENT
==================================================

Menu 13. Nginx ต้อง:

- CLI Only
- Lightweight
- ใช้ RAM ต่ำ
- ใช้ Native Nginx/systemd
- ไม่สร้าง Web UI
- ไม่สร้าง Database เพิ่ม
- ไม่สร้าง Background Service เพิ่ม
- รองรับ Production Server
- เน้น Security
- มี Backup ก่อนเปลี่ยน Configuration
- มี Validation ก่อน Apply
- มี Rollback/Restore
- มี Health Check หลัง Apply
- ไม่ทำให้ Nginx เดิมเสียหาย

ห้ามแก้ไข Menu อื่นของระบบ
และห้ามสร้างฟังก์ชันซ้ำกับ Module อื่น
ให้ Menu 13 เรียกใช้ฟังก์ชันกลางของระบบที่มีอยู่แล้วเมื่อสามารถทำได้