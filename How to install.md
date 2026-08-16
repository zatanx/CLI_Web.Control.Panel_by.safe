# How to Install

Documentation version: v1.1.8 (2026-08-16)

## Requirements

- Ubuntu Server 22.04 or 24.04 LTS (`amd64` or `arm64`)
- At least 1 GB RAM and 5 GB free disk space
- Root or sudo access
- Working DNS and internet access
- A clean server is recommended; the installer may refuse existing non-default Nginx sites

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/zatanx/CLI_Web.Control.Panel_by.safe.git
cd CLI_Web.Control.Panel_by.safe
```

### 2. Install the minimal profile

Install the core system with PHP 8.3 as the only PHP version:

```bash
sudo bash install.sh --profile minimal --php 8.3
```

These are the default options, so the following command is equivalent:

```bash
sudo bash install.sh
```

### 3. Ubuntu 22.04

Ubuntu 22.04 requires permission to use the PHP PPA for some PHP versions:

```bash
sudo bash install.sh --profile minimal --php 8.3 --enable-php-ppa
```

### 4. Install the standard profile

Install PHP 8.2, 8.3, and 8.4 with additional security audit tools:

```bash
sudo bash install.sh --profile standard --php 8.3 --enable-php-ppa
```

## Verify the installation

Keep the current SSH session open, verify a second key-based login, then run:

```bash
sudo serverctl health
sudo serverctl security status
sudo serverctl update check
```

Add a website and enable HTTPS:

```bash
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

## Dashboard (Optional)

The Dashboard source code is installed but remains disabled by default. All Dashboard deployments use port `8088`. Public domains require DNS and an HTTPS certificate; localhost and LAN IP deployments use HTTP:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install xxxxxx.com --user myadmin
```

Open a domain Dashboard at:

```text
https://xxxxxx.com:8088/
```

For a localhost or IP address:

```bash
sudo serverctl dashboard install 192.168.2.66 --user myadmin
```

Open it at:

```text
http://192.168.2.66:8088/
```

Or use localhost on the server:

```bash
sudo serverctl dashboard install localhost --user myadmin
```

```text
http://localhost:8088/
```

The Dashboard uses the same hostname as the website and is accessed only through port `8088`. There is no need to create a `dashboard.` hostname or add a hosts-file entry:

```text
LAN/IP:  http://192.168.2.66:8088/
Domain: https://xxxxxx.com:8088/
```

If UFW is enabled, allow this port from your LAN, for example:

```bash
sudo serverctl firewall add 8088 tcp 192.168.2.0/24
```

See [DASHBOARD.md](DASHBOARD.md) for the Dashboard security model and uninstall instructions.

### Configure Bot Protection for login

In the Dashboard, open `Bot Protection` and select a service:

- `Google reCAPTCHA v3` uses a Google reCAPTCHA Site Key and Secret Key.
- `Cloudflare Turnstile` uses a Cloudflare Turnstile Site Key and Secret Key.

Enter the keys and select `Save Bot Protection`. The server verifies the token before allowing login and never displays the Secret Key again. Select `Disabled` and save if protection is not required.

Bot Protection settings remain enabled according to the selected provider. Login keeps the local-access rule: `localhost` and private IPs such as `192.168.2.66:8088` do not request a bot challenge, while a domain such as `https://xxxxxx.com:8088` does.

After five failed logins within ten minutes, login is locked and Fail2Ban blocks the IP with UFW for one hour.

Blocked IPs are listed in the Dashboard `Fail2Ban` menu or with:

```bash
sudo serverctl fail2ban list
```

The server must have outbound HTTPS access to Google or Cloudflare to verify tokens. Select `Disabled` when the closed system has no internet access.

## Open the main menu

```bash
sudo serverctl
```

## Updating

Update serverctl from GitHub:

```bash
sudo serverctl update serverctl
```

Check the installed version:

```bash
sudo serverctl version
```

---

# วิธีติดตั้ง

เวอร์ชันเอกสาร: v1.1.8 (16-08-2026)

## ความต้องการของระบบ

- Ubuntu Server 22.04 หรือ 24.04 LTS (`amd64` หรือ `arm64`)
- RAM อย่างน้อย 1 GB และพื้นที่ว่างอย่างน้อย 5 GB
- มีสิทธิ์ root หรือ sudo
- DNS และอินเทอร์เน็ตใช้งานได้
- แนะนำให้ใช้เครื่องใหม่ ตัวติดตั้งอาจหยุดทำงานหากมี Nginx site เดิมที่ไม่ใช่ค่าเริ่มต้น

## ขั้นตอนติดตั้ง

### 1. ดาวน์โหลดโปรเจกต์

```bash
git clone https://github.com/zatanx/CLI_Web.Control.Panel_by.safe.git
cd CLI_Web.Control.Panel_by.safe
```

### 2. ติดตั้งแบบ Minimal

ติดตั้งระบบหลักและ PHP 8.3 เพียงเวอร์ชันเดียว:

```bash
sudo bash install.sh --profile minimal --php 8.3
```

ตัวเลือกนี้เป็นค่าเริ่มต้น ดังนั้นคำสั่งด้านล่างจึงทำงานเทียบเท่ากัน:

```bash
sudo bash install.sh
```

### 3. Ubuntu 22.04

Ubuntu 22.04 ต้องอนุญาตให้ใช้ PHP PPA สำหรับ PHP บางเวอร์ชัน:

```bash
sudo bash install.sh --profile minimal --php 8.3 --enable-php-ppa
```

### 4. ติดตั้งแบบ Standard

ติดตั้ง PHP 8.2, 8.3 และ 8.4 พร้อมเครื่องมือตรวจสอบความปลอดภัยเพิ่มเติม:

```bash
sudo bash install.sh --profile standard --php 8.3 --enable-php-ppa
```

## ตรวจสอบหลังติดตั้ง

ให้เปิด SSH session เดิมไว้ ตรวจสอบการเข้าสู่ระบบด้วย SSH key จาก session ที่สอง แล้วรัน:

```bash
sudo serverctl health
sudo serverctl security status
sudo serverctl update check
```

เพิ่มเว็บไซต์และเปิดใช้งาน HTTPS:

```bash
sudo serverctl website add example.com --php 8.3
sudo serverctl ssl enable example.com --email admin@example.com
```

## Dashboard (ตัวเลือกเสริม)

Dashboard จะติดตั้ง source code ไว้แต่ปิดการใช้งานเป็นค่าเริ่มต้น ทุก Dashboard ใช้ port `8088` สำหรับ domain สาธารณะต้องมี DNS และใบรับรอง HTTPS ส่วน localhost และ IP ในวง LAN ใช้ HTTP ได้:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install xxxxxx.com --user myadmin
```

เข้า Dashboard ของ domain ที่:

```text
https://xxxxxx.com:8088/
```

สำหรับ localhost หรือ IP address:

```bash
sudo serverctl dashboard install 192.168.2.66 --user myadmin
```

เข้าใช้งานที่:

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

Dashboard ใช้ hostname เดียวกับเว็บไซต์และเข้าใช้งานผ่าน port `8088` เท่านั้น ไม่ต้องสร้าง hostname `dashboard.` หรือเพิ่มรายการในไฟล์ hosts:

```text
LAN/IP:  http://192.168.2.66:8088/
Domain: https://xxxxxx.com:8088/
```

หากเปิดใช้งาน UFW ให้อนุญาต port นี้จากวง LAN เช่น:

```bash
sudo serverctl firewall add 8088 tcp 192.168.2.0/24
```

ดูรูปแบบความปลอดภัยและคำสั่งถอนการติดตั้งได้ที่ [DASHBOARD.md](DASHBOARD.md)

### ตั้งค่า Bot Protection สำหรับหน้า Login

ใน Dashboard ให้เปิดเมนู `Bot Protection` แล้วเลือก Service:

- `Google reCAPTCHA v3` ใช้ Site Key และ Secret Key จาก Google reCAPTCHA
- `Cloudflare Turnstile` ใช้ Site Key และ Secret Key จาก Cloudflare Turnstile

กรอก Key แล้วเลือก `Save Bot Protection` ระบบจะตรวจสอบ token ฝั่ง server ก่อนอนุญาตให้ Login และจะไม่แสดง Secret Key กลับมา หากไม่ต้องการใช้ให้เลือก `Disabled` แล้วบันทึก

การตั้งค่า Bot Protection จะมีสถานะตาม Provider ที่เลือกไว้เสมอ แต่หน้า Login ยังคงใช้กฎเดิม: `localhost` และ Private IP เช่น `192.168.2.66:8088` ไม่เรียก Bot ส่วน domain เช่น `https://xxxxxx.com:8088` จะเรียกใช้ Bot Protection

หาก Login ผิดครบ 5 ครั้งภายใน 10 นาที ระบบจะล็อกการ Login และ Fail2Ban จะบล็อก IP ด้วย UFW เป็นเวลา 1 ชั่วโมง

รายการ IP ที่ถูกบล็อกดูได้ที่ Dashboard เมนู `Fail2Ban` หรือใช้คำสั่ง:

```bash
sudo serverctl fail2ban list
```

Server ต้องเชื่อมต่อ HTTPS ออกไปยัง Google หรือ Cloudflare เพื่อยืนยัน token หากเป็นระบบปิดที่ไม่มีอินเทอร์เน็ตให้เลือก `Disabled`

## เข้าเมนูหลัก

```bash
sudo serverctl
```

## การอัปเดต

อัปเดต serverctl จาก GitHub:

```bash
sudo serverctl update serverctl
```

ตรวจสอบเวอร์ชันที่ติดตั้ง:

```bash
sudo serverctl version
```
