import 'package:shared_preferences/shared_preferences.dart';

class WalletStorageService {
  static const String _activeWalletIdKey = 'active_wallet_id';

  Future<String?> getActiveWalletId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_activeWalletIdKey);
    } catch (e) {

      return null;
    }
  }

  Future<void> setActiveWalletId(String walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activeWalletIdKey, walletId);
    } catch (e) {

    }
  }

  Future<void> clearActiveWalletId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeWalletIdKey);
    } catch (e) {

    }
  }
}
