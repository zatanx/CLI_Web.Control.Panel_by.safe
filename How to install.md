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

Dashboard จะถูกติดตั้งเฉพาะ source code และปิดการใช้งานไว้เป็นค่าเริ่มต้น โดย Dashboard ทุกแบบใช้ port `8088` แยกจากเว็บไซต์ สำหรับ domain ต้องมี DNS และ HTTPS certificate ส่วน localhost/IP ใช้ HTTP ได้:

The Dashboard source code is installed but remains disabled by default. All Dashboard deployments use port `8088`. Public domains require DNS and an HTTPS certificate; localhost and LAN IP deployments use HTTP:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install xxxxxx.com --user myadmin
```

สำหรับ domain ให้เข้าใช้งานด้วย:

```text
https://xxxxxx.com:8088/
```

สำหรับ localhost หรือ IP address:

```bash
sudo serverctl dashboard install 192.168.2.66 --user myadmin
```

เข้าใช้งานด้วย:

```text
http://192.168.2.66:8088/
```

หรือใช้ localhost บนเครื่อง Server:

```bash
sudo serverctl dashboard install localhost --user myadmin
```

```text
http://localhost:8088/
```

Dashboard จะใช้ hostname เดียวกับเว็บไซต์ และแยกการเข้าใช้งานด้วย port `8088` เท่านั้น
ไม่ต้องสร้าง `dashboard.` hostname หรือเพิ่มรายการในไฟล์ `hosts`:

```text
LAN/IP:  http://192.168.2.66:8088/
Domain: https://xxxxxx.com:8088/
```

หากเปิดใช้งาน UFW ให้อนุญาต port นี้จากวง LAN ของคุณ เช่น:

```bash
sudo serverctl firewall add 8088 tcp 192.168.2.0/24
```

ดูรายละเอียดด้านความปลอดภัยและคำสั่งถอนการติดตั้งได้ที่ [DASHBOARD.md](DASHBOARD.md)

See [DASHBOARD.md](DASHBOARD.md) for the Dashboard security model and uninstall instructions.

### ตั้งค่า Bot Protection สำหรับหน้า Login

ใน Dashboard ให้เปิดเมนู `Bot Protection` แล้วเลือก Service ที่ต้องการ:

- `Google reCAPTCHA v3` ใช้ Site Key และ Secret Key จาก Google reCAPTCHA
- `Cloudflare Turnstile` ใช้ Site Key และ Secret Key จาก Cloudflare Turnstile

กรอก Site Key และ Secret Key แล้วกด `Save Bot Protection` ระบบจะตรวจสอบ token ฝั่ง server ก่อนอนุญาตให้ Login และจะไม่แสดง Secret Key กลับใน Dashboard หากไม่ต้องการใช้ ให้เลือก `Disabled` แล้วบันทึก

เมื่อเข้า Dashboard ผ่าน `localhost` หรือ Private IP เช่น `192.168.2.66:8088` ระบบจะ bypass Bot Protection สำหรับการใช้งานภายใน LAN แต่เมื่อเข้าเป็น domain เช่น `https://xxxxxx.com:8088` จะเรียกใช้ Bot Protection ตาม Service ที่เลือก

หาก Login ผิดครบ 5 ครั้งภายใน 10 นาที ระบบจะล็อกการ Login และ Fail2Ban จะบล็อก IP ด้วย UFW เป็นเวลา 1 ชั่วโมง

หมายเหตุ: Bot Protection ต้องให้ Server เชื่อมต่อ HTTPS ออกไปยังบริการของ Google หรือ Cloudflare เพื่อยืนยัน token หากระบบปิดไม่มี Internet ให้เลือก `Disabled`

### เข้าเมนูหลัก 
```bash
sudo serverctl
```

## การอัปเดตระบบ / Update

```bash
sudo serverctl update serverctl
```

ตรวจสอบ Version:

```bash
sudo serverctl version
```
