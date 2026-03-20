# Dokploy - Open Source Edition

**Versi:** 0.27.1+ (Open Source - Tanpa Fitur Berbayar)

Dokploy adalah Platform as a Service (PaaS) self-hosted yang gratis dan open source. Ini adalah versi yang telah dihapus semua fitur berbayar/enterprise dari versi komersial.

## ⚠️ Perbedaan dari Versi Komersial

Versi ini **TIDAK** memiliki fitur-fitur berikut (yang ada di versi komersial 0.28.x):

- ❌ SSO (Single Sign-On) - OIDC/SAML
- ❌ Whitelabeling / Custom Branding
- ❌ Audit Logs
- ❌ Custom Roles
- ❌ License Key System
- ❌ Stripe Billing / Subscription
- ❌ Enterprise Features

Versi ini menggunakan **lisensi Apache 2.0 murni** dan bebas digunakan tanpa batasan.

---

## 🚀 Migrasi dari Dokploy 0.27.1

Jika Anda sudah menggunakan Dokploy 0.27.1 di VPS, ikuti panduan ini untuk upgrade.

### Opsi 1: Replace Repository (Recommended)

Jika Anda menginstall Dokploy dengan cara clone repository:

```bash
# 1. Backup data penting
cd /path/to/dokploy
docker run --rm -v dokploy_data:/data -v $(pwd)/backup:/backup alpine tar czf /backup/data-backup.tar.gz /data

# 2. Stop semua container Dokploy
docker stop $(docker ps -q --filter name=dokploy)

# 3. Backup database PostgreSQL
docker exec dokploy-postgres pg_dump -U postgres dokploy > backup/database-backup.sql

# 4. Hapus repository lama
cd ..
rm -rf dokploy

# 5. Clone repository open-source ini
git clone https://github.com/YOUR_USERNAME/dokploy.git
cd dokploy

# 6. Restore file .env dari backup lama
cp /path/to/old/dokploy/apps/dokploy/.env apps/dokploy/.env

# 7. Build dan jalankan
pnpm install
pnpm run dokploy:build
pnpm run dokploy:start
```

### Opsi 2: Update via Docker (Jika Pakai Docker Image)

Jika Anda menggunakan Docker image resmi:

```bash
# 1. Backup database
docker exec dokploy-postgres pg_dump -U postgres dokploy > backup.sql

# 2. Stop container
docker stop dokploy

# 3. Hapus container lama
docker rm dokploy

# 4. Pull image baru (jika ada) atau build dari source
# Lihat instruksi di bawah untuk build dari source

# 5. Jalankan container baru dengan volume yang sama
docker run -d \
  --name dokploy \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v dokploy_data:/etc/dokploy \
  -p 3000:3000 \
  your-username/dokploy:latest
```

---

## 📋 Database Migration

Karena versi ini menghapus beberapa kolom enterprise dari database, Anda perlu menjalankan migration:

### Manual Database Cleanup

```bash
# Connect ke PostgreSQL
docker exec -it dokploy-postgres psql -U postgres -d dokploy

# Hapus kolom enterprise dari tabel "user"
ALTER TABLE "user" 
  DROP COLUMN IF EXISTS "enableEnterpriseFeatures",
  DROP COLUMN IF EXISTS "isValidEnterpriseLicense",
  DROP COLUMN IF EXISTS "stripeCustomerId",
  DROP COLUMN IF EXISTS "stripeSubscriptionId",
  DROP COLUMN IF EXISTS "serversQuantity",
  DROP COLUMN IF EXISTS "licenseKey",
  DROP COLUMN IF EXISTS "enablePaidFeatures",
  DROP COLUMN IF EXISTS "trustedOrigins";

# Hapus tabel yang tidak digunakan lagi
DROP TABLE IF EXISTS "sso_provider";
DROP TABLE IF EXISTS "auditLog";
DROP TABLE IF EXISTS "organizationRole";

# Hapus kolom whitelabeling dari webServerSettings
ALTER TABLE "webServerSettings" 
  DROP COLUMN IF EXISTS "whitelabelingConfig";

# Exit
\q
```

### Atau Gunakan Script Migration Otomatis

```bash
# Setelah clone repository
cd dokploy
pnpm install

# Jalankan migration
pnpm run migration:run
```

### Opsi 3: Migration via Docker (Untuk Pengguna Script Install)

Jika Anda menginstall Dokploy menggunakan `install.sh` atau menjalankannya di Docker Swarm, Anda bisa menjalankan migration langsung di dalam container:

```bash
# Jalankan migration otomatis di dalam container
docker exec -it $(docker ps -q -f name=dokploy) pnpm run migration:run
```

---

## 🛠️ Build dari Source

### Prerequisites

- Node.js 24.4.0 (gunakan `nvm`)
- pnpm 10.22.0+
- Docker

### Langkah-langkah

```bash
# 1. Clone repository
git clone https://github.com/YOUR_USERNAME/dokploy.git
cd dokploy

# 2. Install dependencies
pnpm install

# 3. Setup environment
cp apps/dokploy/.env.example apps/dokploy/.env
# Edit .env sesuai kebutuhan

# 4. Build
pnpm run dokploy:build

# 5. Start
pnpm run dokploy:start
```

### Development Mode

```bash
# Jalankan development server
pnpm run dokploy:dev
```

---

## 🐳 Docker Build

Jika ingin build Docker image sendiri:

```bash
# Build image
pnpm run docker:build

# Atau build dengan tag custom
docker build -t your-username/dokploy:latest -f Dockerfile .
```

---

## 📁 Struktur File Penting

```
dokploy/
├── apps/
│   ├── dokploy/          # Main application
│   │   ├── .env          # Environment variables
│   │   ├── server/       # Backend server
│   │   └── pages/        # Next.js pages
│   ├── api/              # API service
│   └── schedules/        # Scheduled tasks
├── packages/
│   └── server/           # Shared server utilities
└── Dockerfile
```

---

## 🔧 Environment Variables

File `.env` yang penting:

```bash
# Database
DATABASE_URL="postgresql://postgres:password@localhost:5432/dokploy"

# Authentication
BETTER_AUTH_SECRET="your-secret-key-here"

# Server
PORT=3000
HOST=0.0.0.0

# Docker
DOKPLOY_DOCKER_HOST=unix:///var/run/docker.sock
```

---

## ⚙️ Commands

| Command | Deskripsi |
|---------|-----------|
| `pnpm run dokploy:setup` | Setup awal (buat database, directories, dll) |
| `pnpm run dokploy:dev` | Jalankan development server |
| `pnpm run dokploy:build` | Build untuk production |
| `pnpm run dokploy:start` | Start production server |
| `pnpm run migration:run` | Jalankan database migration |
| `pnpm run migration:generate` | Generate migration baru |
| `pnpm run reset-password` | Reset password admin |

---

## 🔐 Reset Password Admin

Jika lupa password admin:

```bash
pnpm run reset-password
```

---

## 📝 Changelog Perubahan dari Versi Komersial

### Dihapus:
- Semua kode di folder `/proprietary/`
- Integrasi Stripe (billing, subscription, webhook)
- SSO providers (OIDC, SAML)
- Whitelabeling configuration
- Audit logging system
- Custom roles
- License key validation
- Enterprise feature flags (`enableEnterpriseFeatures`, `isValidEnterpriseLicense`)
- `IS_CLOUD` environment variable dan logic terkait

### Diubah:
- `LICENSE.MD` → Apache 2.0 murni (tanpa proprietary clause)
- Database schema → Dihilangkan kolom enterprise
- Authentication → Hanya email/password + 2FA (tanpa SSO)
- Permission system → Tanpa enterprise-only resources

### Tetap Ada:
- ✅ Deploy applications (Node.js, PHP, Python, Go, Ruby, dll)
- ✅ Database management (MySQL, PostgreSQL, MongoDB, MariaDB, Redis)
- ✅ Automated backups
- ✅ Docker Compose support
- ✅ Multi-server support
- ✅ Traefik integration
- ✅ Real-time monitoring
- ✅ CLI/API
- ✅ Notifications (Slack, Discord, Telegram, Email)
- ✅ 2FA authentication
- ✅ Git providers (GitHub, GitLab, Bitbucket, Gitea)

---

## 🐛 Troubleshooting

### Error: "Column does not exist"

Jika dapat error tentang kolom yang tidak ada setelah upgrade, jalankan manual database cleanup (lihat bagian **Database Migration** di atas).

### Error: "Module not found: @dokploy/server/services/proprietary/*"

Ini berarti ada kode yang masih mengimport modul proprietary yang sudah dihapus. Pastikan Anda menggunakan versi codebase ini yang sudah dibersihkan.

### Container tidak bisa start

Cek log:
```bash
docker logs dokploy
```

Pastikan Docker socket ter-mount dengan benar:
```bash
-v /var/run/docker.sock:/var/run/docker.sock
```

---

## 📚 Dokumentasi

Dokumentasi lengkap tersedia di: https://docs.dokploy.com

**Catatan:** Beberapa fitur di dokumentasi resmi mungkin mengacu pada fitur enterprise yang sudah dihapus dari versi ini.

---

## 🤝 Kontribusi

Silakan fork dan submit pull request untuk improvement. Pastikan:
1. Tidak menambahkan fitur berbayar/enterprise kembali
2. Tetap gunakan lisensi Apache 2.0
3. Test perubahan di environment lokal sebelum submit

---

## 📄 Lisensi

**Apache License 2.0**

Copyright 2026-present Dokploy Technology, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and limitations under the License.

---

## ⚠️ DISCLAIMER

Versi ini adalah versi open-source yang **TIDAK AFILIASI** dengan Dokploy Technology, Inc. Ini adalah versi komunitas yang dihapus semua fitur berbayarnya untuk penggunaan pribadi dan tim kecil.

Untuk fitur enterprise dan support resmi, kunjungi: https://dokploy.com
