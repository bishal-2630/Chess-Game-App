import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'django_auth_service.dart';
import 'config.dart';
import '../utils/logger.dart';

/// A simple class to mimic the RewardItem from google_mobile_ads
class UnityReward {
  final int amount;
  final String type;
  UnityReward(this.amount, this.type);
}

class UnityAdService {
  static final UnityAdService _instance = UnityAdService._internal();
  factory UnityAdService() => _instance;
  UnityAdService._internal();

  bool _isInitialized = false;
  bool _isLoadingAd = false;
  bool _isAdLoaded = false;

  // Unity Ads IDs from Dashboard
  static String get gameId {
    if (Platform.isAndroid) return '6077792';
    if (Platform.isIOS) return '6077793';
    return '';
  }

  static String get rewardedPlacementId {
    if (Platform.isAndroid) return 'Rewarded_Android';
    if (Platform.isIOS) return 'Rewarded_iOS';
    return '';
  }

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      AppLogger.i('🎬 Initializing Unity Ads (Game ID: $gameId)...');
      await UnityAds.init(
        gameId: gameId,
        testMode: false, // Set to false for real ads
        onComplete: () {
          AppLogger.i('✅ Unity Ads Initialization Complete');
          _isInitialized = true;
          loadRewardedAd(); // Start loading the first ad immediately
        },
        onFailed: (error, message) {
          AppLogger.e('❌ Unity Ads Initialization Failed: $error - $message');
          _isInitialized = false;
        },
      );
    } catch (e) {
      AppLogger.e('❌ Error initializing Unity Ads: $e');
      _isInitialized = false;
    }
  }

  void loadRewardedAd() {
    if (!_isInitialized || _isLoadingAd) return;
    
    _isLoadingAd = true;
    _isAdLoaded = false;
    AppLogger.i('🎬 Unity Ads: Loading placement $rewardedPlacementId...');
    
    UnityAds.load(
      placementId: rewardedPlacementId,
      onComplete: (placementId) {
        AppLogger.i('✅ Unity Ads Load Complete: $placementId');
        _isAdLoaded = true;
        _isLoadingAd = false;
      },
      onFailed: (placementId, error, message) {
        AppLogger.e('❌ Unity Ads Load Failed: $placementId - $error - $message');
        _isAdLoaded = false;
        _isLoadingAd = false;
      },
    );
  }

  void showRewardedAd({
    required Function(UnityReward) onUserEarnedReward, 
    Function(String)? onError,
  }) {
    if (!_isInitialized) {
      init();
      onError?.call("Ad service is initializing. Please try again in a few seconds.");
      return;
    }

    if (!_isAdLoaded) {
      loadRewardedAd();
      onError?.call("Ad is still loading. Please wait a few seconds and try again.");
      return;
    }

    _isAdLoaded = false; // Reset state for the next ad
    UnityAds.showVideoAd(
      placementId: rewardedPlacementId,
      onStart: (placementId) => AppLogger.i('🎬 Ad started: $placementId'),
      onClick: (placementId) => AppLogger.i('🎬 Ad clicked: $placementId'),
      onSkipped: (placementId) {
        AppLogger.w('⚠️ Ad skipped: $placementId');
        onError?.call("Ad was skipped. No reward granted.");
        loadRewardedAd(); // Reload for next time
      },
      onComplete: (placementId) async {
        AppLogger.i('✅ Ad completed: $placementId');
        
        final reward = UnityReward(10, 'coins');
        AppLogger.i('💎 User earned reward: ${reward.amount} ${reward.type}');
        
        final newBalance = await _rewardUser(reward.amount);
        if (newBalance != null) {
          onUserEarnedReward(reward);
        } else {
          onError?.call("Could not credit coins. Please check your connection.");
        }
        loadRewardedAd(); // Preload next ad
      },
      onFailed: (placementId, error, message) {
        AppLogger.e('❌ Ad failed to show: $placementId - $error - $message');
        onError?.call("Failed to show ad: $message");
        loadRewardedAd(); // Try reloading
      },
    );
  }

  Future<int?> _rewardUser(int amount) async {
    try {
      final authService = DjangoAuthService();
      final rewardAmount = amount > 0 ? amount : 10;

      AppLogger.i('💰 Calling reward-coins API with amount=$rewardAmount ...');

      final response = await authService.authenticatedRequest(
        '${AppConfig.baseUrl}reward-coins/',
        method: 'POST',
        body: json.encode({'amount': rewardAmount}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final int newBalance = data['new_balance'];
          if (authService.currentUser != null) {
            final userData = Map<String, dynamic>.from(authService.currentUser!);
            userData['coins'] = newBalance;
            authService.updateCurrentUser(userData);
          }
          AppLogger.i('✅ Coins updated to $newBalance');
          return newBalance;
        }
      }
      return null;
    } catch (e) {
      AppLogger.e('❌ Error calling reward-coins: $e');
      return null;
    }
  }

  bool get isAdLoaded => _isAdLoaded;
  bool get isLoading => _isLoadingAd;
}
