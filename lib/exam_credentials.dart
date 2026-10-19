import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SavedLogin {
  const SavedLogin(this.account, this.password);
  final String account;
  final String password;
}

class ExamCredentialStore {
  const ExamCredentialStore();
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'exam_saved_login_v1';

  Future<SavedLogin?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    final account = value['account'];
    final password = value['password'];
    if (account is! String ||
        password is! String ||
        account.isEmpty ||
        password.isEmpty) {
      await clear();
      return null;
    }
    return SavedLogin(account, password);
  }

  Future<void> save(SavedLogin login) => _storage.write(
    key: _key,
    value: jsonEncode({'account': login.account, 'password': login.password}),
  );
  Future<void> clear() => _storage.delete(key: _key);
}
