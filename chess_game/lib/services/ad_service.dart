import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
  bool _isLoading = false;
  int _loadAttempts = 0;

  // TODO: When ready to go live on Play Store, swap the test IDs below with
  // the real IDs that are commented out next to them.
  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-3940256099942544/5224354917'; // Test ID (works debug + release)
      // return 'ca-app-pub-5824509928975992/9268961527'; // Real ID — uncomment after Play Store publish
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // Test ID
      // return 'YOUR_REAL_IOS_AD_UNIT_ID'; // Real ID — replace when going live
    } else {
      throw UnsupportedError("Unsupported platform");
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      AppLogger.i('🎬 Initializing AdMob...');
      await MobileAds.instance.initialize();
      _isInitialized = true;
      loadRewardedAd();
    } catch (e) {
      AppLogger.e('❌ Failed to initialize AdMob: $e');
      _isInitialized = false;
    }
  }

  void loadRewardedAd() {
    if (!_isInitialized || _isLoading) return;

    _isLoading = true;
    AppLogger.i('🎬 Loading rewarded ad (Attempt ${_loadAttempts + 1})...');

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          AppLogger.i('✅ Rewarded ad loaded successfully');
          _rewardedAd = ad;
          _isAdLoaded = true;
          _isLoading = false;
          _loadAttempts = 0;
          
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              AppLogger.i('🎬 Ad dismissed');
              ad.dispose();
              _isAdLoaded = false;
              loadRewardedAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              AppLogger.e('❌ Failed to show ad: $error');
              ad.dispose();
              _isAdLoaded = false;
              loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          AppLogger.w('⚠️ Rewarded ad failed to load: $error');
          _isAdLoaded = false;
          _rewardedAd = null;
          _isLoading = false;
          _loadAttempts++;

          // Retry with exponential backoff (max 1 minute delay)
          if (_loadAttempts < 10) {
            int delaySeconds = pow(2, min(_loadAttempts, 6)).toInt();
            AppLogger.i('🎬 Retrying ad load in $delaySeconds seconds...');
            Future.delayed(Duration(seconds: delaySeconds), () {
              loadRewardedAd();
            });
          }
        },
      ),
    );
  }

  void showRewardedAd({required Function(RewardItem) onUserEarnedReward, Function(String)? onError}) {
    if (!_isInitialized) {
      init();
      onError?.call("Ad service is initializing. Please try again in a few seconds.");
      return;
    }
    
    if (_isAdLoaded && _rewardedAd != null) {
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) async {
        AppLogger.i('💎 User earned reward: ${reward.amount} ${reward.type}');
        await _rewardUser(reward.amount.toInt());
        onUserEarnedReward(reward);
      });
    } else {
      if (_isLoading) {
        onError?.call("Ad is still loading. Please wait a moment...");
      } else {
        onError?.call("Ad is not ready yet. Attempting to reload...");
        loadRewardedAd();
      }
    }
  }

  Future<void> _rewardUser(int amount) async {
    try {
      final authService = DjangoAuthService();
      // Ensure we reward at least 10 coins if the ad value is low/zero (like test ads)
      final rewardAmount = amount > 0 ? amount : 10;
      
      final response = await authService.authenticatedRequest(
        '${AppConfig.baseUrl}reward-coins/',
        method: 'POST',
        body: json.encode({'amount': rewardAmount}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          if (authService.currentUser != null) {
            final userData = Map<String, dynamic>.from(authService.currentUser!);
            userData['coins'] = data['new_balance'];
            authService.updateCurrentUser(userData);
          }
          
          AppLogger.i('💰 User reward successful: ${data['new_balance']} coins');
        }
      }
    } catch (e) {
      AppLogger.e('❌ Error rewarding user: $e');
    }
  }

  bool get isAdLoaded => _isAdLoaded;
  bool get isLoading => _isLoading;
}
