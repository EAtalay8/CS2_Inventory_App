# CS2 Portfolio App — Roadmap & Sorun Takibi
*Son Güncelleme: 2026-02-23*

---

## 🔴 Aktif Sorunlar (Bugs)

### 1. WiFi'de Rate Limit Hatası
**Durum:** ✅ Fix uygulandı (23 Feb 2026) — WiFi testi bekleniyor
**Belirtiler:**
- WiFi üzerinden "Update Prices" butonuna basılınca Exception/404/Rate Limit hatası.
- 3 gün beklenmiş olsa bile hata devam ediyor.
- Mobil veriye geçince sorunsuz çalışıyor.

**Kök Neden Analizi:**
- Steam, ev WiFi IP adresini uzun süreli olarak rate limit'e almış olabilir.
- `_fetchAndSavePrice()` fonksiyonu Steam Market'e istek atarken **hiçbir header göndermiyor** (User-Agent vs.), bu da Steam tarafında bot olarak algılanma riskini artırıyor.
- Envanter çekme (`_fetchRawInventoryFromSteam`) fonksiyonu header kullanıyor ama fiyat çekme fonksiyonu kullanmıyor — bu tutarsızlık sorun yaratabilir.
- İstekler arasında 3.5 saniye bekleniyor ama ~285 item için bu toplamda ~16 dakika demek. Bu süre boyunca aynı IP'den sürekli istek gitmesi Steam'i tetikliyor olabilir.

**Çözüm Önerileri:**
- [x] `_fetchAndSavePrice()`'a browser-benzeri header'lar eklendi
- [x] Adaptive delay eklendi (başarı: 3.5s, hata: 5s, 3+ hata: 15s)
- [x] Rate limit hatası alındığında retry + exponential backoff uygulandı (429 → 10s/20s/30s)
- [x] Hata alındığında cache'deki veriler korunuyor (envanter artık 0'lanmıyor)

---

## 📋 Geliştirme Yol Haritası

### Öncelik 1 — Kısa Vadeli (Bug Fix & UX)

#### 1.1 Inventory Sayfası: Kar/Zarar Sıralaması
**Dosya:** `inventory_page.dart`
- [ ] **Kar Miktarına Göre Sıralama** — Toplam $ kar/zarar büyükten küçüğe
- [ ] **Kar Yüzdesine Göre Sıralama** — ROI % büyükten küçüğe
- Mevcut `SortOption` enum'una iki yeni seçenek eklenmeli

#### 1.2 Ana Sayfa: Top Movers Stack Sorunu
**Dosya:** `main.dart` → `_buildTopMovers()`
- [ ] Aynı item birden fazla kez gözüküyor (her asset ayrı gözüküyor)
- [ ] Çözüm: `classid` veya `name` bazında gruplama yapılmalı, adet (xN) badge ile gösterilmeli
- Market sayfasında zaten bu gruplama var, aynı mantık buraya taşınmalı

#### 1.3 Inventory: Görünüm Tercihinin Hatırlanması
**Dosya:** `inventory_page.dart`
- [ ] Grid/List görünüm seçimi `SharedPreferences` ile kaydedilmeli
- [ ] Sayfa açıldığında son tercih yüklenmeli
- [ ] App kapatılıp açılsa bile tercih korunmalı

#### 1.4 Market & Top Movers: Item Detail Navigasyonu ✅
**Dosyalar:** `market_page.dart`, `main.dart`
- [x] Market sayfasındaki itemlere tıklanınca `ItemDetailPage`'e gidiyor
- [x] Ana sayfadaki Top Movers kartlarına tıklanınca `ItemDetailPage`'e gidiyor
- ~~Market sayfasında `onTap` şu an boş (TODO var)~~ → Tamamlandı (23 Feb 2026)

#### 1.5 Fiyat Güncellemede Akıllı Kategori Gruplaması (Smart Batching)
**Dosya:** `inventory_service.dart`
- [ ] Envanterdeki item isimlerini parse ederek silah/kategori çıkarımı yapma (AK-47, M4A4, Case, Sticker vb.)
- [ ] Her kategori grubu için hedeflenmiş `search/render` batch isteği atma (1 istekte 100 ilgili item)
- [ ] Phase 2'ye (slow update) kalan item sayısını minimize ederek toplam güncelleme süresini 30 dk'dan 2-3 dk'ya düşürme

#### 1.6 Inventory Sayfası: Hiyerarşik Checkbox Filtresi
**Dosya:** `inventory_page.dart`
- [ ] Envanteri kategorilere ayırarak filtreleyebilme (Weapons, Cases, Stickers, Graffitis vb.)
- [ ] Weapons kategorisi altına alt-kategoriler (AK-47, M4A1-S, AWP vb.) ekleme
- [ ] Checkbox tabanlı, çoklu seçim yapılabilen bir filtreleme UI (örn: drawer veya modal bottom sheet)

#### 1.7 Uygulama İçi Geliştirici Konsolu (Developer Console)
**Dosyalar:** `main.dart`, `inventory_service.dart`
- [ ] "Update Prices" butonu altındaki ilerleme metnini kaldırma
- [ ] Arka planda çalışan API isteklerini, rate limit hatalarını ve bekleme sürelerini gösteren bir mini terminal UI (Bottom Sheet) ekleme
- [ ] `InventoryService` içine detaylı log (log stream) yapısı kurma

---

### Öncelik 2 — Orta Vadeli (Performans & Özellik)

#### 2.1 Fiyat Güncelleme Hızı İyileştirmesi
**Dosya:** `inventory_service.dart`
- [ ] Yeni `search/render` toplu çekim motoru entegre edilecek
- [ ] Itemleri 100'lük paketler halinde (max 200) saniyeler içinde güncelliyor
- [ ] Eksik kalan nadir itemler için otomatik tekli fallback eklendi
- Not: Geliştirme aşamasında. (23 Feb 2026)

#### 2.2 Market Sayfası: Zaman Aralığı Filtresi ✅
**Dosya:** `market_page.dart`, `inventory_service.dart`
- [x] 1 Gün / 1 Hafta / 1 Ay seçenekleri (SegmentedButton)
- [x] Seçilen aralığa göre fiyat değişimi hesaplanıyor
- [x] `history.json`'daki item bazlı fiyat geçmişi kullanılıyor
- Not: Tamamlandı (23 Feb 2026)

---

### Öncelik 3 — Uzun Vadeli (Yeni Özellikler)

#### 3.1 Steam Market Tarayıcı (Envanter Dışı İtemler)
- [ ] Envanterde olmayan Steam Market itemlerini arayıp inceleyebilme
- [ ] Steam Market `search/render` API'si entegrasyonu
- [ ] Watchlist'e ekleme özelliği (satın almadan takip)
- [ ] Fiyat alarmı kurabilme (opsiyonel, ileri aşama)
- Detaylı analiz: bkz. **Analiz B — Envanter Dışı İtemleri Çekme**

---
---

## 🔬 Analiz A — Steam Market'ten Direkt Fiyat Çekme (3. Parti API Olmadan)

### Şu Anki Yöntem: `priceoverview` Endpoint'i

**Kullandığımız URL:**
```
https://steamcommunity.com/market/priceoverview/?currency=1&appid=730&market_hash_name=AK-47%20|%20Redline%20(Field-Tested)
```

**Nasıl çalışıyor:**
- Her item için **tek tek** istek atıyoruz.
- JSON dönüyor: `lowest_price`, `median_price`, `volume`.
- İstekler arası 3.5 saniye bekliyoruz.

**Sorunlar:**
| Sorun | Detay |
|-------|-------|
| Tek item/istek | 285 item = 285 ayrı HTTP isteği |
| Toplam süre | 285 × 3.5s = **~16 dakika** |
| Rate Limit | Steam resmi olarak ~20 istek/dakika izin veriyor ama pratikte daha agresif |
| Shadow Ban | 2025'ten itibaren Steam, düşük hızlarda bile (120s/istek) IP engeli uygulamaya başlamış |
| Header eksikliği | Kodumuzda `_fetchAndSavePrice()` **hiçbir header göndermiyor** — bot gibi algılanıyor |

### Alternatif Yöntem: `search/render` Endpoint'i

**URL Formatı:**
```
https://steamcommunity.com/market/search/render/?appid=730&norender=1&count=100&start=0&sort_column=price&sort_dir=desc
```

**Avantajları:**
| Özellik | Detay |
|---------|-------|
| Batch çekme | Tek istekte **100 item** fiyatı çekilebilir |
| JSON çıktı | `norender=1` parametresiyle direkt JSON döner |
| Kategori filtresi | `category_730_Type[]` ile silah, bıçak vb. filtrelenebilir |
| Fiyat bilgisi | Her item'ın `sell_price_text` ve `sell_price` alanlarında fiyat var |

**Dezavantajları:**
- Fiyat bilgisi "lowest listing" bazlı, `priceoverview`'daki "median price" yok
- Sadece markette aktif listesi olan itemlerin fiyatı gelir
- Kendi envanterinizdeki spesifik itemleri değil, genel market fiyatlarını döndürür
- Currency parametresi güvenilir çalışmıyor (browser locale'e bağlı)

### Karşılaştırma ve Önerilen Strateji

| | `priceoverview` | `search/render` |
|---|---|---|
| İstek başına item | 1 | 100 |
| 285 item için istek | 285 | 3 |
| Toplam süre (tahmini) | ~16 dk | ~15 sn |
| Fiyat doğruluğu | Yüksek (median + lowest) | Orta (sadece lowest listing) |
| Rate limit riski | Çok yüksek | Düşük |

**Önerilen Hibrit Yaklaşım:**
1. **Ana güncelleme:** `search/render` ile toplu fiyat çek (hızlı, ~15 saniye)
2. **Yüksek değerli itemler:** Sadece pahalı/önemli itemler için `priceoverview` ile detaylı fiyat al (median price gerekiyorsa)
3. **Header ekleme:** Tüm isteklere browser-benzeri header'lar eklenmeli (User-Agent, Accept, Referer)
4. **Exponential backoff:** Rate limit hatası alınca bekleme süresini kademeli artır

### 3. Parti API Alternatifi (Referans)

Eğer Steam direkt erişim sorun çıkarmaya devam ederse:
- **PriceEmpire API** — Ücretsiz tier var, tek istekte tüm CS2 fiyatları
- **CSFloat API** — Float değerleri + fiyat bilgisi
- **SteamWebAPI.com** — Steam verisi üzerine sarmalama (wrapper) API

---

## 🔬 Analiz B — Envanter Dışı İtemleri Çekme

### Steam Market Search API

Steam Market'teki tüm CS2 itemlerini aramak ve listelemek için kullanılabilecek endpoint:

**URL:**
```
https://steamcommunity.com/market/search/render/?appid=730&norender=1&query=AK-47&start=0&count=100&sort_column=price&sort_dir=asc
```

### Parametreler

| Parametre | Açıklama | Örnek |
|-----------|----------|-------|
| `appid` | Oyun ID (CS2 = 730) | `730` |
| `norender` | JSON formatında dön | `1` |
| `query` | Arama terimi | `AK-47`, `Karambit`, `Gloves` |
| `start` | Sayfalama offset | `0`, `100`, `200`... |
| `count` | Sayfa başına sonuç (max 100) | `100` |
| `sort_column` | Sıralama kolonu | `price`, `name`, `quantity` |
| `sort_dir` | Sıralama yönü | `asc`, `desc` |
| `category_730_Type[]` | Item türü filtresi | `tag_CSGO_Type_Rifle` |
| `category_730_Weapon[]` | Silah filtresi | `tag_weapon_ak47` |
| `category_730_Exterior[]` | Durum filtresi | `tag_WearCategory0` (FN) |
| `l` | Dil | `english` |

### Dönen JSON Yapısı

```json
{
  "success": true,
  "start": 0,
  "pagesize": 100,
  "total_count": 1250,
  "results": [
    {
      "name": "AK-47 | Redline (Field-Tested)",
      "hash_name": "AK-47 | Redline (Field-Tested)",
      "sell_listings": 4523,
      "sell_price": 1245,
      "sell_price_text": "$12.45",
      "app_icon": "...",
      "app_name": "Counter-Strike 2",
      "asset_description": {
        "appid": 730,
        "classid": "310777286",
        "icon_url": "...",
        "type": "Covert Rifle",
        "market_hash_name": "AK-47 | Redline (Field-Tested)"
      }
    }
  ]
}
```

### Uygulama Planı

**Aşama 1 — Temel Arama:**
- [ ] Arama çubuğu ile item adı yazıp sonuçları listeleme
- [ ] Sonuçlarda fiyat, listing sayısı, item resmi gösterme
- [ ] Pagination desteği (sayfa sayfa yükleme)

**Aşama 2 — Kategori Filtreleri:**
- [ ] Silah türü (Rifle, Pistol, Knife, Gloves vb.) filtresi
- [ ] Wear durumu (FN, MW, FT, WW, BS) filtresi
- [ ] Fiyat aralığı filtresi

**Aşama 3 — Watchlist Entegrasyonu:**
- [ ] Market'te bulunan itemi "Takip Et" ile watchlist'e ekleme
- [ ] Fiyat güncellemelerinde watchlist itemlerini de dahil etme
- [ ] Watchlist itemlerinin fiyat geçmişini tutma

### Rate Limit Notu

`search/render` endpoint'i de rate limit'e tabi ama `priceoverview`'dan daha toleranslı. Önerilen:
- İstekler arası minimum **3 saniye** bekleme
- Sayfa başına **max 100** sonuç
- Retry + exponential backoff uygulanmalı

---

## 🔬 Analiz C — Google Play & iOS App Store'a Yayınlama

### Maliyet Karşılaştırması

| | Google Play | iOS App Store |
|---|---|---|
| Geliştirici Hesabı | **$25** (tek seferlik) | **$99/yıl** (yıllık abonelik) |
| Mac Gereksinimi | ❌ Gerekmiyor | ⚠️ Build için gerekli (CI/CD ile aşılabilir) |
| İnceleme Süresi | 1-7 gün | 1-3 gün (bazen daha uzun) |
| Test Zorunluluğu | ✅ Yeni hesaplar: 12-20 test kullanıcısıyla 14 gün kapalı test | ❌ TestFlight önerilir ama zorunlu değil |
| Yayın Sonrası Ücret | Yok | Yıllık $99 yenilenecek |

---

### Google Play Store — Adım Adım

#### Ön Gereksinimler
- [ ] Google Play Developer hesabı oluştur ($25)
- [ ] Yeni hesaplar için: Android cihaz doğrulaması gerekli
- [ ] DUNS numarası gerekliliği yok (bireysel hesap için)

#### Teknik Hazırlık
- [ ] `android/app/build.gradle.kts`'te `applicationId` benzersiz olmalı (ör: `com.yourname.cs2portfolio`)
- [ ] `targetSdk` → **35** (Android 15) olmalı (Ağustos 2025 zorunluluğu)
- [ ] `versionCode` ve `versionName` güncellenmeli (`pubspec.yaml` → `version: 1.0.0+1`)
- [ ] Uygulama ikonu oluşturulmalı (512×512 px, `flutter_launcher_icons` paketi)
- [ ] **Upload Keystore** oluşturulmalı (imzalama anahtarı — KAYBETME!)

#### Build
```bash
flutter build appbundle --release
# Çıktı: build/app/outputs/bundle/release/app-release.aab
```
> ⚠️ Google Play artık sadece **AAB** (App Bundle) kabul ediyor. APK kabul edilmiyor.

#### Play Console Gereksinimleri
- [ ] **Store Listing:** Uygulama adı, kısa açıklama (80 karakter), uzun açıklama
- [ ] **Ekran Görüntüleri:** En az 2 adet (telefon), tercihen tablet de
- [ ] **Feature Graphic:** 1024×500 px (mağaza banner'ı)
- [ ] **Privacy Policy URL:** Web'de barındırılan gizlilik politikası (GitHub Pages veya basit site)
- [ ] **Data Safety Formu:** Hangi verilerin toplandığını beyan et (Steam ID, fiyat verileri vb.)
- [ ] **Content Rating:** IARC anketini doldur
- [ ] **Financial Features Beyanı:** Finansal özellik beyanı (Ekim 2025 zorunluluğu)
- [ ] **Target Audience:** Hedef kitle (13+ veya 18+ — sanal item yatırımı olduğu için)

#### Yeni Hesap Zorunluluğu: Kapalı Test
> ⚠️ Kasım 2023'ten sonra açılan hesaplar için Production yayını öncesi zorunlu.
- [ ] Uygulamayı **Internal Testing** track'ine yükle
- [ ] En az **12-20 benzersiz test kullanıcısı** ekle (gerçek Google hesapları)
- [ ] **14 gün kesintisiz** test süreci tamamlanmalı
- [ ] Ancak bundan sonra Production'a geçiş izni verilir

---

### iOS App Store — Adım Adım

#### Ön Gereksinimler
- [ ] Apple Developer Program'a kaydol ($99/yıl)
- [ ] Apple ID gerekli
- [ ] **Mac bilgisayar** — veya **CI/CD servisi** (aşağıya bak)

#### Mac Olmadan iOS Build: CI/CD ile Çözüm

Mac'in yoksa bile iOS'a yayınlayabilirsin. **Codemagic** gibi CI/CD servisleri bulut tabanlı Mac makinelerinde build yapıyor:

| CI/CD Servisi | Ücretsiz Plan | Ücretli Plan |
|---|---|---|
| **Codemagic** | 500 dk/ay (macOS) | $75/ay'dan başlıyor |
| **GitHub Actions** | macOS runner mevcut | Ücretsiz (public repo) |
| **Bitrise** | Sınırlı ücretsiz | $36/ay'dan başlıyor |

**Codemagic ile akış:**
1. Flutter projeyi GitHub/GitLab'a push et
2. Codemagic'te proje kur → iOS workflow seç
3. Apple Developer hesap bilgilerini (App Store Connect API Key) ekle
4. Codemagic otomatik olarak: build → sign → IPA oluştur → App Store Connect'e yükle
5. App Store Connect web arayüzünden (Mac gerekmez) listing'i tamamla

#### Teknik Hazırlık (iOS)
- [ ] `ios/Runner.xcodeproj` → Bundle Identifier ayarla (ör: `com.yourname.cs2portfolio`)
- [ ] **Xcode 16+** ile build (2025 zorunluluğu) — CI/CD bunu otomatik halleder
- [ ] Uygulama ikonu (1024×1024 px)
- [ ] `Info.plist`'te gerekli izin açıklamaları

#### App Store Connect Gereksinimleri
- [ ] **Uygulama Bilgileri:** Ad, alt başlık, açıklama, anahtar kelimeler
- [ ] **Ekran Görüntüleri:** iPhone (6.7" ve 6.1"), iPad (opsiyonel)
- [ ] **Privacy Policy URL:** Zorunlu
- [ ] **App Privacy Labels:** Hangi verilerin toplandığını detaylı beyan
- [ ] **Age Rating:** Yaş derecelendirme anketi
- [ ] **Demo Hesap:** Review ekibi için test giriş bilgileri (login gerektiriyorsa)

---

### Bu Uygulama İçin Özel Dikkat Edilecekler

| Konu | Detay |
|------|-------|
| **Steam API Kullanımı** | Steam'in resmi olmayan API'lerini kullanıyoruz — mağaza açıklamasında bunu belirtmek gerekebilir |
| **Fikri Mülkiyet** | "CS2", "Counter-Strike" Valve'ın ticari markası — uygulama adında doğrudan kullanma |
| **Finansal İçerik** | Sanal item "yatırım" analizi yapıyor — Google'ın finansal özellik beyanı gerekli |
| **Privacy Policy** | Steam ID topluyoruz — bu gizlilik politikasında belirtilmeli |
| **Uygulama Adı Önerisi** | "CS2 Portfolio" yerine daha genel bir ad (ör: "Skin Tracker", "Inventory Analyzer") daha güvenli |
| **Minimal Yaş** | 13+ veya 16+ uygun olabilir (finansal izleme + oyun içeriği) |

### Önerilen Yayınlama Stratejisi

1. **Önce Google Play** — Daha ucuz ($25 vs $99/yıl), Mac gerektirmiyor, daha hızlı başlarsın
2. **Kapalı test süreci** — 14 günlük test süreci boyunca bug'ları fix et
3. **iOS ikinci aşama** — Uygulama stabil olduktan sonra Codemagic ile iOS build'i kur
4. **Sürekli güncelleme** — Her iki mağazada da düzenli güncellemeler önemli (sıralama + kullanıcı güveni)

---

## 📝 Notlar
- Rate limit sorunu en kritik konu, kullanıcı deneyimini doğrudan etkiliyor.
- Fiyat güncelleme hızı ve rate limit birbirine bağlı — biri çözülürse diğeri de kolaylaşır.
- `search/render` endpoint'i hem fiyat güncelleme hızını hem de market tarayıcı özelliğini çözebilecek **anahtar** endpoint.
- 3. parti API entegrasyonu son çare olarak düşünülmeli — önce Steam'in kendi endpoint'leri denenecek.
- Google Play yayını daha erişilebilir ($25 tek seferlik) — iOS için Mac veya CI/CD servisi gerekli.
