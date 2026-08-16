# วิธีติดตั้ง / How to Install

## ความต้องการของระบบ / Requirements

### ไทย

- Ubuntu Server 22.04 หรือ 24.04 LTS (`amd64` หรือ `arm64`)
- RAM อย่างน้อย 1 GB และพื้นที่ว่างอย่างน้อย 5 GB
- มีสิทธิ์ root หรือ sudo
- เชื่อมต่อ DNS และอินเทอร์เน็ตได้
- แนะนำให้ใช้เครื่องใหม่ หากมี Nginx site เดิมที่ไม่ใช่ค่าเริ่มต้น ตัวติดตั้งอาจหยุดทำงาน

### English

- Ubuntu Server 22.04 or 24.04 LTS (`amd64` or `arm64`)
- At least 1 GB RAM and 5 GB free disk space
- Root or sudo access
- Working DNS and internet access
- A clean server is recommended; the installer may refuse existing non-default Nginx sites

## ขั้นตอนติดตั้ง / Installation

### 1. ดาวน์โหลดโปรเจกต์ / Clone the repository

```bash
git clone https://github.com/zatanx/CLI_Web.Control.Panel_by.safe.git
cd CLI_Web.Control.Panel_by.safe
```

### 2. ติดตั้งแบบ Minimal / Install the minimal profile

ติดตั้งระบบหลักและ PHP 8.3 เพียงเวอร์ชันเดียว:

Install the core system with PHP 8.3 as the only PHP version:

```bash
sudo bash install.sh --profile minimal --php 8.3
```

ตัวเลือกนี้เป็นค่าเริ่มต้น ดังนั้นคำสั่งด้านล่างจึงเทียบเท่ากัน:

These are the default options, so the following command is equivalent:

```bash
sudo bash install.sh
```

### 3. Ubuntu 22.04

Ubuntu 22.04 ต้องอนุญาตให้ใช้ PHP PPA สำหรับ PHP บางเวอร์ชัน:

Ubuntu 22.04 requires permission to use the PHP PPA for some PHP versions:

```bash
sudo bash install.sh --profile minimal --php 8.3 --enable-php-ppa
```

### 4. ติดตั้งแบบ Standard / Install the standard profile

ติดตั้ง PHP 8.2, 8.3, 8.4 พร้อมเครื่องมือตรวจสอบระบบ:

Installs PHP 8.2, 8.3, and 8.4 with additional security audit tools:

```bash
sudo bash install.sh --profile standard --php 8.3 --enable-php-ppa
```

## ตรวจสอบหลังติดตั้ง / Verify the installation

### ไทย

ให้เปิด SSH session เดิมไว้ ตรวจสอบการเข้าสู่ระบบด้วย SSH key จาก session ที่สอง แล้วรัน:

Keep the current SSH session open, verify a second key-based login, then run:

```bash
sudo serverctl health
sudo serverctl security status
sudo serverctl update check
```

เพิ่มเว็บไซต์และเปิดใช้งาน HTTPS:

Add a website and enable HTTPS:

```bash
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

## Dashboard (ตัวเลือกเสริม / Optional)

### ไทย

Dashboard จะถูกติดตั้งเฉพาะ source code และปิดการใช้งานไว้เป็นค่าเริ่มต้น หลังจากสร้าง DNS record และมี HTTPS certificate สำหรับ hostname แยกแล้ว ให้เปิดใช้งานด้วย:

The Dashboard source code is installed but remains disabled by default. After creating a DNS record and obtaining an HTTPS certificate for a dedicated hostname, enable it with:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install dashboard.example.com
```

ดูรายละเอียดด้านความปลอดภัยและคำสั่งถอนการติดตั้งได้ที่ [DASHBOARD.md](DASHBOARD.md)

See [DASHBOARD.md](DASHBOARD.md) for the Dashboard security model and uninstall instructions.

### เข้าเมนูหลัก 
```bash
sudo serverctl
```

## การอัปเดตระบบ / Update

```bash
sudo serverctl update serverctl
```
