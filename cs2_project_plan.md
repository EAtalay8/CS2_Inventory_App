# CS2 Inventory App - Durum Analizi ve Yol Haritası

## 1. Proje Durum Özeti

### Mevcut Altyapı

**Frontend (Flutter - `cs2_portfolio_app`):**
*   **Ana Sayfa (`HomePage`):** Toplam portföy değeri, günlük değişim yüzdesi ve grafik için yer tutucular (placeholder) içeriyor.
*   **Envanter Sayfası (`InventoryPage`):** Backend'den çekilen eşyaları listeliyor.
*   **Servis:** `InventoryService`, yerel ağdaki (`192.168.1.25:3000`) backend'e bağlanıp JSON verisini işliyor.

**Backend (Node.js - `cs2_backend`):**
*   Express.js üzerinde çalışan bir sunucu (`server.js`).
*   `/inventory/:steamid` endpoint'i üzerinden Steam Community API'sine bağlanıp CS2 envanterini (730 app ID) çekiyor.
*   **Sayfalama (Pagination):** Yapısı kurulmuş, çoklu sayfa envanterleri çekip birleştiriyor.
*   **Veri İşleme:** Eşya isimlerini, ikonlarını ve türlerini ayrıştırıp temiz bir JSON formatında sunuyor.

## 2. Eksikler ve Yapılması Gerekenler

1.  **Fiyatlandırma Sistemi:** Şu an sadece eşya bilgisi var, fiyat bilgisi yok. Steam Market veya 3. parti API'lerden (Buff163, CSGO Backpack vb.) fiyat çekilmesi gerekiyor.
2.  **Veritabanı Entegrasyonu:** Geçmiş fiyatları ve kullanıcı portföyünün zaman içindeki değişimini tutmak için bir veritabanı (Firebase, MongoDB veya PostgreSQL) şart.
3.  **Yatırım Analizi:** Alış fiyatı girme, kar/zarar hesaplama mantıkları eklenmeli.
4.  **Grafik Entegrasyonu:** Flutter tarafında `fl_chart` gibi bir kütüphane ile gerçek veriye dayalı grafikler çizilmeli.

---

## 3. Diğer AI İçin Hazırlanan Prompt

Aşağıdaki metni kopyalayıp diğer AI'ya yapıştırabilirsin:

```text
Merhaba, elimde geliştirmekte olduğum bir CS2 Inventory & Yatırım Takip uygulaması var. Proje iki ana parçadan oluşuyor:

1.  **Backend (Node.js & Express):**
    *   Şu an çalışır durumda. Steam API'sine bağlanıp verilen Steam ID'nin CS2 envanterini çekiyor.
    *   Pagination (sayfalama) sorunsuz çalışıyor, tüm envanteri tek bir JSON listesi olarak döndürüyor.
    *   Dönen veri: `assetid`, `classid`, `name`, `icon` (URL), `type`.

2.  **Frontend (Flutter):**
    *   Temel UI iskeleti hazır.
    *   Ana sayfada "Toplam Değer", "Günlük Değişim" ve "Grafik" alanları var (şu an dummy data).
    *   Backend'den gelen veriyi `InventoryService` ile çekip listeyebiliyorum.

**Hedefim:**
Bu uygulamayı tam kapsamlı bir yatırımcı asistanına dönüştürmek.

**Senden İstediklerim (Sırasıyla Planlayalım):**

1.  **Fiyat Entegrasyonu (Backend):**
    *   Çekilen her item için güncel fiyat bilgisini alabileceğim bir yapı kurmalıyız. (Steam Market API veya güvenilir ücretsiz 3. parti API önerisi ve entegrasyonu).
    *   Fiyatları önbelleğe (cache) alarak her istekte API'yi yormayan bir yapı istiyorum (Redis veya basit bir JSON/DB cache).

2.  **Veritabanı & Takip (Backend):**
    *   Kullanıcının envanterinin toplam değerini günlük olarak kaydedecek bir veritabanı yapısı (MongoDB veya Firebase olabilir).
    *   Böylece "Portföyüm geçen hafta ne kadardı, bugün ne kadar?" sorusuna cevap verebileceğiz.

3.  **Gelişmiş Analiz (Frontend & Backend):**
    *   Item detayına girdiğimde o itemin fiyat geçmişini (grafik verisi) görebilmeliyim.
    *   Flutter tarafında `fl_chart` kullanarak ana sayfadaki placeholder grafiği canlandırmalıyız.

4.  **Yatırımcı Araçları:**
    *   Manuel olarak "Alış Fiyatı" girebilme özelliği. Böylece "Bu itemi 10$'a aldım, şu an 15$, karım %50" gibi analizleri görebileyim.

Şu an kodlara hakimsin, ilk adım olarak **Fiyat Entegrasyonu** kısmından başlayalım. Hangi API'yi önerirsin ve backend'deki `server.js` dosyamı buna göre nasıl güncellemeliyiz?
```
