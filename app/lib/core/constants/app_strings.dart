import 'package:flutter/widgets.dart';

/// Centralized Turkish user-facing copy for the whole app. Keeping every
/// user-visible string in one place makes tone/consistency easy to review
/// and keeps widgets free of inline literals.
@immutable
class AppStrings {
  const AppStrings._();

  // ---------------------------------------------------------------------
  // App-wide
  // ---------------------------------------------------------------------
  static const String appName = 'Cyber Tavla';
  static const String tagline = 'Neon ışıklar altında tavla';
  static const String genericError = 'Bir şeyler ters gitti.';
  static const String ok = 'Tamam';
  static const String cancel = 'Vazgeç';
  static const String back = 'Geri';
  static const String retry = 'Tekrar Dene';
  static const String close = 'Kapat';
  static const String copy = 'Kopyala';
  static const String copied = 'Kopyalandı';
  static const String loading = 'Yükleniyor...';

  // ---------------------------------------------------------------------
  // Home / main menu
  // ---------------------------------------------------------------------
  static const String homeTitle = 'CYBER TAVLA';
  static const String homeSubtitle = 'Neon pullar, gerçek zamanlı düellolar';
  static const String menuSinglePlayer = 'Tek Oyunculu';
  static const String menuMultiplayer = 'Çok Oyunculu';
  static const String menuSettings = 'Ayarlar';
  static const String menuHowToPlay = 'Nasıl Oynanır';
  static const String menuExit = 'Çıkış';
  static const String versionLabel = 'Sürüm';

  // ---------------------------------------------------------------------
  // Single player / bot setup
  // ---------------------------------------------------------------------
  static const String singlePlayerTitle = 'Tek Oyunculu';
  static const String chooseDifficulty = 'Zorluk seviyeni seç';
  static const String difficultyEasy = 'Kolay';
  static const String difficultyEasyDesc = 'Rastgele hamleler yapan rakip';
  static const String difficultyMedium = 'Orta';
  static const String difficultyMediumDesc = 'Taşlarını koruyan, stratejik rakip';
  static const String difficultyHard = 'Zor';
  static const String difficultyHardDesc = 'İleri düzey hamle değerlendirmesi yapan rakip';
  static const String startGame = 'Oyunu Başlat';
  static const String chooseYourColor = 'Rengini seç';
  static const String colorWhite = 'Beyaz';
  static const String colorBlack = 'Siyah';

  // ---------------------------------------------------------------------
  // Online / multiplayer lobby
  // ---------------------------------------------------------------------
  static const String multiplayerTitle = 'Çok Oyunculu';
  static const String createRoom = 'Oda Oluştur';
  static const String joinRoom = 'Odaya Katıl';
  static const String roomCodeLabel = 'Oda Kodu';
  static const String roomCodeHint = 'Örn: A1B2C3';
  static const String enterRoomCode = 'Katılmak için oda kodunu gir';
  static const String yourNickname = 'Takma adın';
  static const String nicknameHint = 'Rumuzunu yaz';
  static const String connecting = 'Sunucuya bağlanılıyor...';
  static const String connectionFailed = 'Sunucuya bağlanılamadı';
  static const String connectionLost = 'Bağlantı koptu, yeniden bağlanılıyor...';
  static const String reconnected = 'Yeniden bağlanıldı';
  static const String waitingForOpponent = 'Rakip bekleniyor...';
  static const String playersWaitingSuffix = 'oyuncu eşleşme bekliyor';
  static const String noOneWaiting = 'Şu an bekleyen oyuncu yok';
  static const String opponentJoined = 'Rakip odaya katıldı';
  static const String opponentLeft = 'Rakip odadan ayrıldı';
  static const String opponentDisconnected = 'Rakibin bağlantısı koptu, bekleniyor...';
  static const String roomFull = 'Oda dolu';
  static const String roomNotFound = 'Oda bulunamadı';
  static const String shareRoomCode = 'Bu kodu rakibinle paylaş';
  static const String leaveRoom = 'Odadan Ayrıl';
  static const String rematch = 'Yeniden Eşleş';
  static const String waitingForRematch = 'Rakibin onayı bekleniyor...';

  // ---------------------------------------------------------------------
  // Game screen (board / dice / turn state)
  // ---------------------------------------------------------------------
  static const String yourTurn = 'Sıra sende';
  static const String opponentTurn = 'Rakibin oynuyor';
  static const String rollDice = 'Zar At';
  static const String rolling = 'Zar atılıyor...';
  static const String noMovesAvailable = 'Oynanabilecek hamle yok, sıra geçiliyor';
  static const String turnSkipped = 'Sıra geçildi';
  static const String pieceOnBar = 'Pul bar\'da bekliyor';
  static const String mustEnterFromBar = 'Önce bar\'daki pulunu girmelisin';
  static const String bearOff = 'Toplama Bölgesi';
  static const String forfeit = 'Oyunu Terk Et';
  static const String confirmForfeitTitle = 'Oyunu terk et';
  static const String confirmForfeitMessage = 'Oyunu terk etmek istediğine emin misin? Bu, rakibinin galibiyeti sayılacak.';
  static const String pauseMenu = 'Duraklat';
  static const String resumeGame = 'Devam Et';
  static const String backToMenu = 'Ana Menüye Dön';
  static const String moveHistory = 'Hamle Geçmişi';
  static const String checkersOff = 'Toplanan Pul';
  static const String barLabel = 'Bar';

  // ---------------------------------------------------------------------
  // End of game
  // ---------------------------------------------------------------------
  static const String youWin = 'KAZANDIN!';
  static const String youLose = 'KAYBETTİN';
  static const String gammonWin = 'GAMMON ile kazandın!';
  static const String backgammonWin = 'MARS (Backgammon) ile kazandın!';
  static const String opponentDisconnectedWin = 'Rakibin bağlantısı kesildiği için kazandın';
  static const String playAgain = 'Tekrar Oyna';
  static const String returnToMenu = 'Menüye Dön';

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------
  static const String settingsTitle = 'Ayarlar';
  static const String settingSound = 'Ses Efektleri';
  static const String settingMusic = 'Müzik';
  static const String settingVibration = 'Titreşim';
  static const String settingAnimationSpeed = 'Animasyon Hızı';
  static const String settingServerUrl = 'Sunucu Adresi';
  static const String settingServerUrlHint = 'wss://sunucu-adresin';
  static const String settingPlayerName = 'Oyuncu Adı';
  static const String settingAbout = 'Hakkında';
  static const String settingsSaved = 'Ayarlar kaydedildi';

  // ---------------------------------------------------------------------
  // How to play
  // ---------------------------------------------------------------------
  static const String howToPlayTitle = 'Nasıl Oynanır';
  static const String howToPlayIntro =
      'Tavla, iki oyuncunun 15\'er pulu 24 hanelik bir tahtada karşılıklı taşıdığı '
      'klasik bir strateji oyunudur. Amaç, tüm pullarını rakibinden önce '
      'toplama bölgesine (ev bölgesi) getirip tahtadan çıkarmaktır.';
  static const String howToPlayDice =
      'Her turda iki zar atılır. Çift gelirse (örneğin 4-4), o sayı ile dört '
      'hamle yapılır.';
  static const String howToPlayHit =
      'Bir hanede rakibin tek pulu varsa (blot), üzerine gelerek onu vurabilir '
      've bar\'a gönderebilirsin. Bar\'daki pul, tekrar oyuna girmeden başka '
      'hamle yapamaz.';
  static const String howToPlayBearOff =
      'Tüm pullarını kendi ev bölgene getirdiğinde, zar sayılarına göre '
      'pullarını tahtadan çıkarmaya (toplamaya) başlayabilirsin.';
}