import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'dart:convert';
import 'django_auth_service.dart';
import 'config.dart';
import '../utils/logger.dart';

class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isInitialized = false;

  // Test Ad Unit IDs from Google
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    } else {
      throw UnsupportedError("Unsupported platform");
    }
  }

  Future<void> init() async {
    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      loadRewardedAd();
    } catch (e) {
      _isInitialized = false;
    }
  }

  void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isAdLoaded = false;
              loadRewardedAd(); // Load next ad
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _isAdLoaded = false;
              loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isAdLoaded = false;
          _rewardedAd = null;
        },
      ),
    );
  }

  void showRewardedAd({required Function(RewardItem) onUserEarnedReward, Function(String)? onError}) {
    if (!_isInitialized) {
      init();
      if (onError != null) {
        onError("Ad service is initializing. Please try again in a few seconds.");
      }
      return;
    }
    
    if (_isAdLoaded && _rewardedAd != null) {
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) async {
        await _rewardUser(reward.amount.toInt());
        onUserEarnedReward(reward);
      });
    } else {
      if (onError != null) {
        onError("Ad is not ready yet. Please try again soon.");
      }
      loadRewardedAd();
    }
  }

  Future<void> _rewardUser(int amount) async {
    try {
      final authService = DjangoAuthService();
      final response = await authService.authenticatedRequest(
        '${AppConfig.baseUrl}reward-coins/',
        method: 'POST',
        body: json.encode({'amount': amount > 0 ? amount : 10}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Update local user data with new balance
          final userData = Map<String, dynamic>.from(authService.currentUser!);
          userData['coins'] = data['new_balance'];
          authService.updateCurrentUser(userData);
          
          AppLogger.i('💰 User reward successful: ${data['new_balance']} coins');
        }
      }
    } catch (e) {
      AppLogger.e('❌ Error rewarding user: $e');
    }
  }

  bool get isAdLoaded => _isAdLoaded;
}
