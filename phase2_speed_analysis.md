# 🚀 Phase 2 Hız Optimizasyonu Raporu

## Problem

| Metrik | Değer |
|--------|-------|
| Toplam unique marketable item | ~208 |
| Batch'te bulunan | 12 (%6) |
| Phase 2'ye kalan | ~196 |
| Phase 2 süresi (tahmini) | ~30 dk |

## Batch Neden Sadece 12 Buldu?

Mevcut batch phase, Steam Market'te **en popüler 1000 itemi** tarıyor (`sort_column=popular`). Senin envanterindeki itemların büyük çoğunluğu (sticker, graffiti, case, rare skin) bu top 1000'de yerini almıyor. Bu yüzden eşleşme oranı çok düşük.

---

## 💡 Çözüm Önerileri

### 1. 🎯 İtem İsmine Göre Hedefli Batch Arama (En Etkili)

Şu anda: `query=` (boş) + `sort_column=popular` → Genel popüler itemları getirir.

**Öneri:** Envanterdeki itemları silah/kategori bazında grupla ve her grup için ayrı bir batch search yap.

```
Örnek: Envanterde 15 tane "AK-47" varyasyonu varsa:
→ /market/search/render/?query=AK-47&appid=730&count=100&norender=1
→ Tek istekte tüm AK-47 fiyatları gelir 🎯
```

**Nasıl çalışır:**
- Envanterdeki item isimlerinden silah adlarını çıkar (AK-47, M4A4, AWP, Glock, USP-S, vb.)
- Sticker, Case, Graffiti gibi kategorileri ayrı ara
- Her kategori için 1 istek = 100 sonuç → Çok daha yüksek eşleşme

**Tahmini etki:**
- 15-20 kategori araması ile **%80-90 eşleşme** sağlanabilir
- Phase 2'ye kalan item sayısı ~20'ye düşer
- **Toplam süre: ~5-7 dk** (şu an ~30 dk)

---

### 2. ⚡ Authenticated Delay Azaltma

Şu an Phase 2'de **her istek arasında 4 saniye** bekleniyor. Steam login cookie ile authenticated isteklerde rate limit daha yüksek.

**Öneri:** Authenticated kullanıcılar için delay'i `4s → 2s` ye düşür.

**Tahmini etki:**
- 196 item × 2s = ~6.5 dk (şu an ~13 dk sadece bekleme)
- Rate limit riski düşük (authenticated session)
- Eğer 429 alırsa otomatik yukarı çek (adaptive delay)

---

### 3. 🔄 Paralel İstekler (2-3 Concurrent)

Şu an istekler tamamen sıralı: bir biter, diğeri başlar.

**Öneri:** Aynı anda 2-3 istek at, sonuçları bekle, sonra sonraki batch.

```
Şu an:   [item1] → bekle → [item2] → bekle → [item3] → bekle
Paralel:  [item1, item2, item3] → bekle → [item4, item5, item6] → bekle
```

**Tahmini etki:**
- Süre **2-3x** düşer
- 2s delay + 3 paralel = 196/3 × 2s = ~2.2 dk 🔥
- Rate limit riski var ama authenticated session ile yönetilebilir

---

### 4. 🏷️ Akıllı Kategori Gruplaması

Batch search'ü tamamen yeniden tasarla. Popülerlik yerine **envantere özel** arama yap:

1. İtem isimlerini parse et → Silah tipi çıkar
2. Benzersiz kategorileri bul (AK-47, M4A4, AWP, Sticker, Case, vb.)
3. Her kategori için 1 search request at
4. Eşleşen fiyatları kaydet

Bu yaklaşım, Çözüm 1'in daha yapılandırılmış hali.

---

### 5. 🗑️ Değersiz İtemleri Atla

Bazı itemlar (<$0.05) güncellemeye değmez: Graffiti, çoğu common sticker, spray vb.

**Öneri:** `type` alanına bakarak graffiti'leri otomatik atla veya son bilinen fiyatı $0.05 altındaysa skip et.

**Tahmini etki:** Item sayısını %10-20 azaltır.

---

## 📊 Kombinasyon Senaryoları

| Senaryo | Tahmini Süre | Karmaşıklık |
|---------|-------------|-------------|
| Mevcut durum | ~30 dk | — |
| Sadece delay azalt (4s→2s) | ~15 dk | Düşük |
| Hedefli batch + delay azalt | ~5 dk | Orta |
| Hedefli batch + delay + paralel (2x) | ~2-3 dk | Orta-Yüksek |
| Hepsini birleştir | **~1-2 dk** | Yüksek |

## Önerim

**Öncelik sırası:**
1. 🔴 **Hedefli batch arama** — En büyük etki, batch'in eşleşme oranını %6'dan %80+'ya çıkarır
2. 🔴 **Authenticated delay azaltma** — Çok kolay, hemen uygulanır
3. 🟡 **Paralel istekler** — Ekstra hız, ama rate limit yönetimi gerekir

Bu 3'ü birleşince **~30 dk → ~2-3 dk** ye düşer.
