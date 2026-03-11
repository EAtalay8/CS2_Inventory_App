# 🔍 Steam Rate Limit Analizi — Update Prices

## Problem Özeti

Daha önce ev WiFi'ında rate limit yeniyordu, mobil veriyle çözülüyordu. Artık **mobil veride de** aynı problem yaşanıyor. Bu, sorunun **IP tabanlı olmadığını** (veya artık sadece IP tabanlı olmadığını) gösteriyor.

---

## 🏗️ Mevcut Sistemin Akışı

Update Prices butonuna basıldığında uygulama şu adımları izliyor:

```
[Inventory Fetch] → [Phase 1: Batch] → [Phase 2: Individual] 
```

### 1. Inventory Fetch (Steam Inventory API)
- **URL**: `steamcommunity.com/inventory/{steamId}/730/2`
- **Sayfa başı**: 75 item (`count=75`)
- **Sayfalar arası bekleme**: 1 saniye
- Envanterin büyüklüğüne göre birden fazla sayfa çekilir (her seferinde)

### 2. Phase 1 — Batch Update (Steam Market Search API)
- **URL**: `steamcommunity.com/market/search/render/`
- **5 sayfa × 100 item** = Toplam 500 item taranır
- **Sayfalar arası bekleme**: 4 saniye
- **429 (Rate Limit) durumunda**: 30 saniye bekler, 1 kez retry yapar

### 3. Phase 2 — Individual Update (Steam PriceOverview API)
- **URL**: `steamcommunity.com/market/priceoverview/`
- Batch'te bulunamayan her item için tek tek çekilir
- **Başarılı olursa bekleme**: 4 saniye
- **1 hata sonrası bekleme**: 8 saniye
- **2+ ardışık hata sonrası bekleme**: 25 saniye
- **Her item için 3 retry** hakkı var (exponential backoff: 10s, 20s, 30s)

---

## 🔴 Rate Limit'in Olası Nedenleri

### 1. ⚡ Steam'in Rate Limit Politikası Değişti (En Muhtemel)

Steam, 2024-2025 itibariyle Market API rate limitlerini **önemli ölçüde sıkılaştırdı**. Artık sadece IP'ye değil, şunlara da bakıyor olabilir:

| Faktör | Açıklama |
|--------|----------|
| **HTTP Fingerprint** | Aynı User-Agent, header sırası → Aynı "istemci" olarak tanınıyorsun |
| **Request Paterni** | Her 4 sn'de bir gelen market istekleri, bot davranışı olarak algılanıyor |
| **Global Rate Limit** | Steam, tüm anonymous istekler için **dakikada ~20-25 istek** limiti uygulayabilir |
| **Session/Cookie** | Cookie olmadan yapılan istekler daha agresif throttle'lanıyor |

> [!IMPORTANT]
> Mobil veride de aynı problemi yaşaman, **sorunun IP'den bağımsız olduğunu** kanıtlıyor. Steam muhtemelen **istek sayısı + header pattern** bazlı limit uyguluyor.

### 2. 📊 İstek Hacmi Çok Yüksek

Mevcut kod akışında bir "Update Prices" çağrısında toplam yapılan istek sayısı:

| Aşama | İstek Sayısı |
|-------|-------------|
| Inventory Fetch | ~4-5 istek (envanter büyüklüğüne bağlı) |
| Phase 1: Batch | 5 istek |
| Phase 2: Individual | Batch'te bulunamayan her item için 1-3 istek |

Eğer envanterinde ~285 **marketable** item varsa ve batch'te sadece ~150'sini bulursa:
- **Phase 2'de ~135 item × 1-3 istek = 135-405 istek** daha yapılır
- 4 sn aralıkla bile bu **~9-27 dakika** sürer

> [!WARNING]
> Steam, tek bir ses siondan bu kadar sürekli istek gelmesini kesinlikle bot trafiği olarak görür. Rate limit kaçınılmaz!

### 3. 🌐 Ev WiFi + Mobil Veri Aynı Sonuç = Steam Tarafında Global Throttle

İki farklı IP'den aynı sonucu alman, Steam'in rate limit'inin **IP-bağımsız** bir mekanizma da içerdiğini gösteriyor. Olasılıklar:

| Mekanizma | Açıklama |
|-----------|----------|
| **Cookie/Session bazlı** | Cookie göndermiyoruz, anonim istekler daha sıkı throttle'lanır |
| **Header fingerprinting** | Aynı User-Agent + header kombinasyonu, tüm IP'lerden aynı "client" olarak algılanır |
| **Endpoint-level global limit** | Steam, `priceoverview` endpoint'ini genel olarak kısmış olabilir |
| **CGNAT** | Mobil operatörler aynı IP'yi paylaşır (Carrier-Grade NAT), başka kullanıcıların istekleri senin limitini yiyebilir |

---

## 💡 Önerilen Çözümler

### Kısa Vadeli (Hemen Uygulanabilir)

#### 1. Phase 2 Delay'leri Artır
Mevcut 4 saniye → **6-8 saniye** arası. Consecutive error bile olmasa temel bekleme süresini artırmak, Steam'in toleransını aşmayı geciktirir.

#### 2. Batch Phase'i Genişlet
5 × 100 yerine **10 × 100 = 1000 item** tara. Batch çok daha verimli (tek istekte 100 fiyat geliyor) ve genelde daha az rate limit yiyor.

#### 3. Steam Login Cookie Kullan
Steam'e giriş yapmış kullanıcıların rate limit çok daha yüksek. Eğer uygulamaya Steam login entegre edilirse, `steamLoginSecure` cookie'sini isteklere ekleyerek authenticated request yapmak mümkün. Bu, limitleri önemli ölçüde artırır.

### Orta Vadeli

#### 4. Akıllı Güncelleme (Sadece Değişenleri Güncelle)
Her seferinde tüm envanterin fiyatını güncellemek yerine:
- Son 24 saatte fiyatı güncellenen itemları **atlayabilirsin**
- Sadece fiyatı hiç olmayan veya 24+ saat eski olanları güncelleyebilirsin
- Bu, istek sayısını %50-70 azaltabilir

#### 5. Alternatif Fiyat API'leri
Steam Market API dışında alternatif kaynaklar kullanılabilir:
- **skinport.com API** (daha yüksek rate limit)
- **csfloat.com API** (market fiyatları)
- **buff.163.com** (Çin pazarı, farklı fiyatlar ama karşılaştırma için)
- Bu API'ler genellikle tek istekte tüm fiyatları verebilir

#### 6. Proxy/Rotation Sistemi (Son çare)
Birden fazla IP üzerinden istek dağıtma. Karmaşık ve maliyetli, bu yüzden son çare olarak düşünülmeli.

---

## 📋 Sonuç ve Öneri

| Öncelik | Çözüm | Etki | Zorluk |
|---------|-------|------|--------|
| 🔴 1 | Batch phase'i 10 sayfaya çıkar | Yüksek | Düşük |
| 🔴 2 | Phase 2 delay'leri artır (6-8s) | Orta | Düşük |
| 🟡 3 | Akıllı güncelleme (skip fresh prices) | Yüksek | Orta |
| 🟡 4 | Alternatif API entegrasyonu | Çok Yüksek | Orta-Yüksek |
| 🟢 5 | Steam login cookie entegrasyonu | Çok Yüksek | Yüksek |

> [!TIP]
> **En hızlı ve en etkili çözüm**: Batch phase'i genişletmek (1) + akıllı güncelleme (3) kombinasyonu. Bu iki değişiklik tek başına istek sayısını %60-80 azaltabilir.

Ne düşünüyorsun? Hangi çözüm(ler)le başlayalım?
