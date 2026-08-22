# Cyber Tavla

Neon ışıklarla süslenmiş, klasik tavla (backgammon) kurallarına sahip; tek oyunculu (bot'a karşı) ve gerçek zamanlı çok oyunculu modları destekleyen bir mobil oyun.

- **İstemci (client):** Flutter 3.x, Riverpod ile durum yönetimi, tahta/pul/zar animasyonları için `CustomPainter`.
- **Oyun motoru:** Saf Dart ile yazılmış, Flutter'a bağımlı olmayan paylaşılan bir modül (`app/lib/shared/`). Kurallar, hamle üretimi/doğrulaması, tahta/zar/oyun durumu modelleri burada yaşar; ileride sunucu tarafında da doğrulama için yeniden kullanılabilecek şekilde tasarlanmıştır.
- **Sunucu:** Node.js + Socket.io ile gerçek zamanlı çok oyunculu altyapı (oda oluşturma/katılma, zar ve hamle senkronizasyonu, bağlantı kopmalarında yeniden bağlanma).

## İçindekiler

- [Klasör yapısı](#klasör-yapısı)
- [Mimari ve tasarım kararları](#mimari-ve-tasarım-kararları)
- [Uygulamayı çalıştırma](#uygulamayı-çalıştırma)
- [Sunucuyu çalıştırma](#sunucuyu-çalıştırma)
- [Android APK: otomatik derleme (GitHub Actions)](#android-apk-otomatik-derleme-github-actions)
- [Dağıtım (deployment)](#dağıtım-deployment)
- [Bot yapay zekâsı](#bot-yapay-zekâsı)
- [Bilinen sınırlamalar ve gelecek çalışmalar](#bilinen-sınırlamalar-ve-gelecek-çalışmalar)

## Klasör yapısı

```
cyber_tavla/
  app/                          Flutter uygulaması
    lib/
      main.dart                 Uygulama giriş noktası
      app/                      Tema ve yönlendirme (routing)
      core/                     Ortak sabitler (renkler, Türkçe metinler) ve widget'lar
      features/
        home/                   Ana menü, "Nasıl Oynanır" ekranı
        game/                   Tahta, zar, pul widget'ları ve oyun ekranı
          board/                Tahta geometrisi, CustomPainter, etkileşim
          dice/                 Zar CustomPainter'ı ve animasyonu
          pieces/               Pul çizimi ve uçuş animasyonu
          screens/              Ana oyun ekranı (yerel / bot modu)
        online/                 Socket.io istemcisi, çok oyunculu lobi ve oyun ekranı
        bot/                    Kademeli bot yapay zekâsı ve zorluk seçim ekranı
        settings/               Ayarlar (ses, animasyon hızı, sunucu adresi, rumuz)
      shared/                   Saf Dart oyun motoru (board, dice, moves, rules, game_state)
    test/                       Oyun motoru birim testleri
    pubspec.yaml
  server/                       Node.js + Socket.io gerçek zamanlı sunucu
    src/
      index.js                  Giriş noktası (Express + Socket.io kurulumu)
      rooms.js                  Oda/eşleşme yönetimi ve olay günlüğü (event log)
      handlers.js                Socket.io olay işleyicileri (protokol)
    package.json
  .github/workflows/
    build_apk.yml                Her push'ta otomatik APK derleyen GitHub Actions iş akışı
  README.md                     (bu dosya)
```

## Mimari ve tasarım kararları

### Neden "saf Dart oyun motoru"?

Tavla kurallarının tamamı (`app/lib/shared/`) Flutter'a hiçbir bağımlılığı olmayan saf Dart sınıflarında yazıldı: `Board`, `Dice`, `Move`, `TavlaRules`, `GameState`. Bunun iki somut faydası var:

1. Flutter arayüz katmanı sadece bu motoru "kullanır"; kural mantığı widget'lardan tamamen ayrıdır, bu da test edilebilirliği ve bakımı kolaylaştırır (bkz. `app/test/rules_test.dart`).
2. İleride bu paket sunucu tarafında (Node.js içinde Dart'ı derleyip çalıştırarak ya da mantığı JavaScript'e taşıyarak) bağımsız hamle doğrulaması için yeniden kullanılabilir — bkz. [Bilinen sınırlamalar](#bilinen-sınırlamalar-ve-gelecek-çalışmalar).

### Neden sunucu, kuralları değil sadece "rölesi" yapıyor?

Gerçek zamanlı sunucu (`server/`) şu anda tavla kurallarını kendisi çalıştırmıyor; bunun yerine:

- Oda/koltuk (white/black) yönetimini yapıyor,
- Zarı **sunucu tarafında, adil bir rastgelelik ile** üretip her iki oyuncuya aynı anda yayınlıyor,
- Bir oyuncunun (kendi istemcisinde zaten kural motoruyla doğrulanmış) hamlesini diğer oyuncuya aktarıyor,
- Her odanın **yetkili olay günlüğünü** (`events`: zar atışları + hamleler) tutuyor.

Bu olay günlüğü, yeniden bağlanma (reconnection) senaryosunu basit ve sağlam kılıyor: bir istemci koptuğunda, tekrar bağlandığında sunucudan tüm günlüğü ister (`sync_state`), `GameState.newGame(startingPlayer: ...)` üzerine bu günlüğü sırayla uygular (`applyRoll` / `applyMove`) ve böylece iki taraf da bağımsız olarak aynı, kesin oyun durumuna ulaşır — sunucunun kuralları bilmesine gerek kalmadan.

Bu, "sunucu tarafında da doğrulama için yeniden kullanılabilir" hedefine giden **ilk aşamadır**; tam bağımsız sunucu tarafı doğrulama (hileli/bozuk bir istemciye karşı) ileride bu Dart motorunun sunucuya taşınmasıyla eklenebilir.

### Görsel/animasyon yaklaşımı

Tahta, pullar ve zarlar `CustomPainter` ile çiziliyor (`board_painter.dart`, `dice_widget.dart`, `piece_widget.dart`). Bir hamle oynandığında, arayüz "gösterilen tahta"yı bir animasyon kuyruğu ile bir adım geriden takip eder: hamleden önceki tahta çizilir, uçan bir pul (`FlyingChecker`) hedefe doğru küçük bir sıçrama eğrisiyle hareket eder, animasyon bitince gerçek (güncel) tahtaya geçilir. Bu teknik hem yerel/bot hem de çevrimiçi modda aynı şekilde çalışır.

## Uygulamayı çalıştırma

Bu depo, Flutter/Android SDK'sının bulunmadığı bir ortamda hazırlandı; bu yüzden APK'nın sizin makinenizde veya GitHub Actions üzerinde derlenmesi gerekiyor.

Yerel bir makinede (Flutter SDK kuruluysa):

```bash
cd app
flutter pub get
flutter run            # bağlı bir cihaz/emülatörde çalıştırır
flutter test           # oyun motoru birim testlerini çalıştırır
flutter build apk      # yerel olarak APK üretir (android/ klasörü otomatik oluşturulur)
```

Not: `android/` (ve `ios/`) platform klasörleri bu depoda commit'lenmemiştir, çünkü hazırlık ortamında `flutter create` çalıştırılamadı. `flutter run` veya `flutter build apk` komutlarını çalıştırmadan önce, eğer `android/` klasörü yoksa şunu çalıştırın:

```bash
cd app
flutter create --platforms=android .
```

Bu komut mevcut `pubspec.yaml` ve `lib/` içeriğinizi **bozmaz**; sadece eksik olan platform iskeletini ekler. GitHub Actions iş akışı bunu otomatik olarak zaten yapıyor (aşağıya bakın).

Uygulama içinden çok oyunculu moda girdiğinizde, Ayarlar ekranından sunucu adresini (`Sunucu Adresi`) dağıttığınız gerçek zamanlı sunucunun adresiyle güncellemeniz gerekir (varsayılan `http://localhost:3000` yalnızca yerel geliştirme içindir).

## Sunucuyu çalıştırma

```bash
cd server
npm install
npm start               # http://localhost:3000 üzerinde dinler
# veya geliştirme sırasında otomatik yeniden başlatma için:
npm run dev
```

Sunucu, `PORT` ortam değişkenini okur (barındırma platformları bunu otomatik ayarlar) ve `/health` ile basit bir sağlık kontrolü uç noktası sunar.

Gerçek zamanlı protokol (Socket.io olayları) hakkında ayrıntılı belgeler `server/src/handlers.js` dosyasının başındaki yorumlarda ve karşılığı olan Flutter tarafında `app/lib/features/online/socket_service.dart` dosyasında yer alır.

## Android APK: otomatik derleme (GitHub Actions)

Bu sandbox ortamında Flutter/Android SDK bulunmadığı için APK burada derlenemedi. Bunun yerine `.github/workflows/build_apk.yml` iş akışı, `main` dalına her push'ta (veya elle tetiklendiğinde) gerçek bir Android SDK'ya sahip GitHub Actions çalıştırıcısında (runner) şunları yapar:

1. Flutter SDK'sını kurar,
2. Eksik olan `android/` platform iskeletini oluşturur (`flutter create --platforms=android .`),
3. Bağımlılıkları indirir, statik analiz ve testleri çalıştırır (bilgi amaçlı, derlemeyi durdurmazlar),
4. `flutter build apk --release` ile gerçek, kurulabilir bir APK üretir,
5. APK'yı hem bir **build artifact** olarak hem de `latest-apk` adında sürekli güncellenen bir **GitHub Release** varlığı olarak yayınlar.

**APK'yı indirmek için:**

- Depodaki **Releases** sekmesine gidin, `latest-apk` adlı (en güncel) sürümü açın ve `app-release.apk` dosyasını indirin, **veya**
- Depodaki **Actions** sekmesinden en son `Build Android APK` çalıştırmasını açın, "Artifacts" bölümünden `cyber-tavla-apk` dosyasını indirin.

APK'yı Android cihazınıza kurarken "bilinmeyen kaynaklardan kuruluma izin ver" ayarını açmanız gerekebilir (uygulama henüz bir mağazada yayınlanmadığı için).

## Dağıtım (deployment)

### Gerçek zamanlı sunucu (Socket.io) — Render veya Railway

Socket.io sunucusu **kalıcı (long-lived) bağlantılar** gerektirdiği için **sunucusuz (serverless) bir platformda** (ör. Vercel) barındırılamaz. Bunun yerine **Render** veya **Railway** gibi kalıcı süreç çalıştırabilen bir servis kullanılmalıdır:

1. `server/` klasörünü ayrı bir servis olarak dağıtın (kök dizin: `server`, başlatma komutu: `npm start`, kurulum komutu: `npm install`).
2. Platformun otomatik atadığı `PORT` ortam değişkenini olduğu gibi kullanın (kod zaten `process.env.PORT` okuyor).
3. İsteğe bağlı olarak `CORS_ORIGIN` ortam değişkenini, Vercel'de barındırılan web istemcisinin adresine ayarlayın.
4. Dağıtım tamamlandığında size verilen genel adresi (ör. `https://cyber-tavla-server.onrender.com`) uygulamanın **Ayarlar > Sunucu Adresi** alanına girin.

### Web/lobi parçası (isteğe bağlı) — Vercel

Vercel, yalnızca **statik/durağan** veya sunucusuz parçalar için kullanılmalıdır — örneğin bir Flutter Web derlemesi ya da basit bir tanıtım/lobi sayfası. Gerçek zamanlı Socket.io sunucusu Vercel'de **çalışmaz**. Flutter Web derlemesini Vercel'e dağıtmak isterseniz:

```bash
cd app
flutter build web
# çıktı: app/build/web — bu klasörü Vercel'e statik site olarak dağıtın
```

## Bot yapay zekâsı

`app/lib/features/bot/bot_ai.dart` içinde kademeli (tiered) bir yapı bulunur:

- **Kolay:** Yasal hamleler arasından tamamen rastgele seçim yapar.
- **Orta:** Her aday hamleyi simüle edip bir sezgisel (heuristic) fonksiyonla puanlar — pip sayısı (yarış ilerlemesi), açık pul (blot) riski, yapılmış (2+ pullu) noktalar, bar ve toplama (bear-off) ilerlemesi.
- **Zor:** Aynı sezgisel fonksiyona ek olarak, rakibin bir sonraki hamlesi için ucuz bir "1 kademe ileri bakış" (shallow look-ahead) uygular — tam bir minimax/expectiminimax araması değil, "rakip iyi oynarsa ne olur" sorusuna ucuz bir yaklaşıklıktır.

Tam bir minimax/expectiminimax araması (zar olasılıklarını birkaç hamle derinliğinde özyinelemeli olarak değerlendiren) bilinçli olarak **gelecek çalışma** olarak bırakılmıştır; "Zor" seviye güçlü bir sezgisel yöntemdir, tam bir çözücü değildir.

## Bilinen sınırlamalar ve gelecek çalışmalar

- **Sunucu tarafı bağımsız doğrulama:** Şu an hamle geçerliliği yalnızca hamleyi yapan istemcinin yerel motoru tarafından kontrol ediliyor; sunucu sadece rölesi yapıyor. Kötü niyetli/bozuk bir istemciye karşı tam koruma için, paylaşılan Dart motorunun sunucu tarafında da (ör. `dart compile js` ile ya da mantığın Node.js'e taşınmasıyla) bağımsız olarak çalıştırılması gerekir.
- **Gelişmiş zar kullanımı kuralı:** Motor, her zarı tek tek ve o anki tahta durumuna göre değerlendirir; resmi tavla kurallarındaki "mümkünse her iki zarı da kullanmak zorunludur, hatta farklı bir sıralama bunu mümkün kılıyorsa o sıralama tercih edilmelidir" kuralının tam optimizasyonunu (tüm hamle sıralamalarını karşılaştırarak) yapmaz. Pratikte hemen her pozisyonda doğru sonucu verir; sınırda kalan nadir pozisyonlar için gelecekte geliştirilebilir.
- **Minimax bot:** Yukarıda açıklandığı gibi, tam bir minimax/expectiminimax arama motoru gelecek çalışma olarak planlanmıştır.
- **Android platform iskeleti:** `android/` klasörü bu depoda commit'lenmemiştir; GitHub Actions iş akışı bunu her derlemede otomatik oluşturur (yukarıya bakın). Yerel geliştirme için de aynı komutu çalıştırmanız gerekir.
- **Sesler/müzik:** Ayarlar ekranında ses/müzik/titreşim anahtarları hazır, ancak gerçek ses dosyaları ve oynatma mantığı bu ilk sürümde eklenmemiştir; bu bir sonraki iyileştirme adımıdır.