# How to Install ( English )

Documentation version: v1.1.10 (2026-08-16)

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
### 2. install
```bash
sudo bash install.sh
```

## Dashboard (Optional)

The Dashboard source code is installed but remains disabled by default. All Dashboard deployments use port `8088`. Public domains require DNS and an HTTPS certificate; localhost and LAN IP deployments use HTTP:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install xxxxxx.com
```

Open a domain Dashboard at:

```text
https://xxxxxx.com:8088/
```

For a localhost or IP address:

```bash
sudo serverctl dashboard install 192.168.2.66
```

Open it at:

```text
http://192.168.2.66:8088/
```

The Dashboard uses the same hostname as the website and is accessed only through port `8088`. There is no need to create a `dashboard.` hostname or add a hosts-file entry:

```text
LAN/IP:  http://192.168.2.66:8088/
Domain: https://xxxxxx.com:8088/
```

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

# วิธีติดตั้ง ( ไทย )

เวอร์ชันเอกสาร: v1.1.10 (16-08-2026)

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

### 2. ติดตั้ง

```bash
sudo bash install.sh
```

## Dashboard (ตัวเลือกเสริม)

Dashboard จะติดตั้ง source code ไว้แต่ปิดการใช้งานเป็นค่าเริ่มต้น ทุก Dashboard ใช้ port `8088` สำหรับ domain สาธารณะต้องมี DNS และใบรับรอง HTTPS ส่วน localhost และ IP ในวง LAN ใช้ HTTP ได้:

```bash
sudo serverctl dashboard status
sudo serverctl dashboard install xxxxxx.com
```

เข้า Dashboard ของ domain ที่:

```text
https://xxxxxx.com:8088/
```

สำหรับ localhost หรือ IP address:

```bash
sudo serverctl dashboard install 192.168.2.66
```

เข้าใช้งานที่:

```text
http://192.168.2.66:8088/
```

```text
LAN/IP:  http://192.168.2.66:8088/
Domain: https://xxxxxx.com:8088/
```

## เข้าเมนูหลัก

```bash
sudo serverctl
```

## การอัปเดต

อัปเดต serverctl จาก GitHub:

```bash
sudo serverctl update serverctl
```

## ตรวจสอบเวอร์ชันที่ติดตั้ง:

```bash
sudo serverctl version
```
