import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  // In a real production app, this key should be generated via key exchange (Diffie-Hellman).
  // For this implementation, we will derive a key from the Chat ID to ensure consistency.

  static String encryptMessage(String plainText, String chatId) {
    try {
      // Create a deterministic key based on the Chat ID (32 chars)
      final keyString = chatId.padRight(32, '*').substring(0, 32);

      // FIX: Changed from .utf8 to .fromUtf8
      final key = encrypt.Key.fromUtf8(keyString);
      final iv = encrypt.IV.fromLength(16);

      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // We combine IV and Encrypted text to allow decryption
      return "${iv.base64}:${encrypted.base64}";
    } catch (e) {
      return plainText; // Fallback
    }
  }

  static String decryptMessage(String encryptedText, String chatId) {
    try {
      final parts = encryptedText.split(':');
      if (parts.length != 2) return encryptedText;

      final keyString = chatId.padRight(32, '*').substring(0, 32);

      // FIX: Changed from .utf8 to .fromUtf8
      final key = encrypt.Key.fromUtf8(keyString);
      final iv = encrypt.IV.fromBase64(parts[0]);

      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      return encrypter.decrypt(encrypt.Encrypted.fromBase64(parts[1]), iv: iv);
    } catch (e) {
      return "Error decrypting";
    }
  }
}
