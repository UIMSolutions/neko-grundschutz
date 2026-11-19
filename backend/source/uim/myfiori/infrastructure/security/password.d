/**
 * Password hashing with PBKDF2-HMAC-SHA256 (OpenSSL) and random tokens.
 * Hash format: "pbkdf2-sha256$<iterations>$<salt base64>$<hash base64>".
 */
module uim.myfiori.infrastructure.security.password;

import std.base64 : Base64;
import std.conv : to, ConvException;
import std.string : split;

import deimos.openssl.crypto : CRYPTO_memcmp;
import deimos.openssl.evp : EVP_sha256, PKCS5_PBKDF2_HMAC;
import deimos.openssl.rand : RAND_bytes;

import uim.myfiori.ports.services : IPasswordHasher;

enum pbkdf2Iterations = 210_000;   // OWASP 2023 recommendation for PBKDF2-HMAC-SHA256
private enum saltLength = 16, keyLength = 32, scheme = "pbkdf2-sha256";

/// Cryptographically secure random bytes.
ubyte[] randomBytes(size_t n) @trusted {
  auto buf = new ubyte[n];
  if (RAND_bytes(buf.ptr, cast(int) n) != 1) throw new Exception("RAND_bytes failed");
  return buf;
}

private ubyte[] derive(const(char)[] password, const(ubyte)[] salt, int iterations) @trusted {
  auto key = new ubyte[keyLength];
  if (PKCS5_PBKDF2_HMAC(password.ptr, cast(int) password.length, salt.ptr, cast(int) salt.length,
      iterations, EVP_sha256(), keyLength, key.ptr) != 1)
    throw new Exception("PBKDF2 failed");
  return key;
}

string hashPassword(string password, int iterations = pbkdf2Iterations) @safe {
  auto salt = randomBytes(saltLength);
  return scheme ~ "$" ~ iterations.to!string ~ "$" ~ Base64.encode(salt).idup ~ "$"
      ~ Base64.encode(derive(password, salt, iterations)).idup;
}

/// Constant time verification; false for malformed hashes.
bool verifyPassword(string password, string encoded) @trusted {
  auto parts = encoded.split("$");
  if (parts.length != 4 || parts[0] != scheme) return false;
  try {
    auto iterations = parts[1].to!int;
    if (iterations < 1000 || iterations > 10_000_000) return false;
    auto salt = Base64.decode(parts[2]);
    auto expected = Base64.decode(parts[3]);
    auto actual = derive(password, salt, iterations);
    return expected.length == actual.length && CRYPTO_memcmp(expected.ptr, actual.ptr, actual.length) == 0;
  } catch (Exception) return false;
}

class DPbkdf2PasswordHasher : IPasswordHasher {
  private int _iterations;
  this(int iterations = pbkdf2Iterations) @safe { _iterations = iterations; }
  string hash(string password) @safe { return hashPassword(password, _iterations); }
  bool verify(string password, string encoded) @safe { return verifyPassword(password, encoded); }
}

@safe unittest {
  auto h = hashPassword("geheim123", 1000);
  assert(verifyPassword("geheim123", h));
  assert(!verifyPassword("geheim124", h));
  assert(!verifyPassword("x", "garbage"));
  assert(hashPassword("a", 1000) != hashPassword("a", 1000));   // salted
}
