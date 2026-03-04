/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "tool/net/lcrypto.h"

#include "libc/stdio/rand.h"
#include "libc/str/str.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include "third_party/mbedtls/chachapoly.h"
#include "third_party/mbedtls/hkdf.h"
#include "third_party/mbedtls/md.h"

#define CHACHAPOLY_KEY_LEN  32
#define CHACHAPOLY_NONCE_LEN 12
#define CHACHAPOLY_TAG_LEN  16

/**
 * AeadEncrypt(key, plaintext[, aad]) → ciphertext
 *
 * Encrypts plaintext using ChaCha20-Poly1305 AEAD.
 *
 * @param key   32-byte encryption key (raw bytes)
 * @param plaintext  data to encrypt
 * @param aad   optional additional authenticated data
 * @return nonce(12) || tag(16) || ciphertext on success
 * @return nil, error on failure
 */
int LuaAeadEncrypt(lua_State *L) {
  size_t kl, pl, al;
  const char *key = luaL_checklstring(L, 1, &kl);
  const char *plaintext = luaL_checklstring(L, 2, &pl);
  const char *aad = luaL_optlstring(L, 3, "", &al);
  int rc;
  mbedtls_chachapoly_context ctx;

  if (kl != CHACHAPOLY_KEY_LEN) {
    return luaL_error(L, "key must be 32 bytes, got %d", (int)kl);
  }

  /* generate random nonce */
  uint8_t nonce[CHACHAPOLY_NONCE_LEN];
  if (getrandom(nonce, sizeof(nonce), 0) != sizeof(nonce)) {
    lua_pushnil(L);
    lua_pushstring(L, "failed to generate random nonce");
    return 2;
  }

  /* allocate output buffer: nonce + tag + ciphertext */
  size_t outlen = CHACHAPOLY_NONCE_LEN + CHACHAPOLY_TAG_LEN + pl;
  uint8_t *out = lua_newuserdata(L, outlen);

  /* copy nonce to output */
  memcpy(out, nonce, CHACHAPOLY_NONCE_LEN);

  /* encrypt */
  mbedtls_chachapoly_init(&ctx);
  rc = mbedtls_chachapoly_setkey(&ctx, (const unsigned char *)key);
  if (rc != 0) {
    mbedtls_chachapoly_free(&ctx);
    lua_pushnil(L);
    lua_pushstring(L, "failed to set key");
    return 2;
  }

  rc = mbedtls_chachapoly_encrypt_and_tag(&ctx,
      pl,
      nonce,
      (const unsigned char *)aad, al,
      (const unsigned char *)plaintext,
      out + CHACHAPOLY_NONCE_LEN + CHACHAPOLY_TAG_LEN,  /* ciphertext */
      out + CHACHAPOLY_NONCE_LEN);                       /* tag */

  mbedtls_chachapoly_free(&ctx);

  if (rc != 0) {
    lua_pushnil(L);
    lua_pushstring(L, "encryption failed");
    return 2;
  }

  lua_pushlstring(L, (const char *)out, outlen);
  return 1;
}

/**
 * AeadDecrypt(key, ciphertext[, aad]) → plaintext
 *
 * Decrypts ciphertext produced by AeadEncrypt using ChaCha20-Poly1305.
 *
 * @param key   32-byte encryption key (raw bytes)
 * @param data  nonce(12) || tag(16) || ciphertext
 * @param aad   optional additional authenticated data
 * @return plaintext on success
 * @return nil, error on failure (including authentication failure)
 */
int LuaAeadDecrypt(lua_State *L) {
  size_t kl, dl, al;
  const char *key = luaL_checklstring(L, 1, &kl);
  const char *data = luaL_checklstring(L, 2, &dl);
  const char *aad = luaL_optlstring(L, 3, "", &al);
  int rc;
  mbedtls_chachapoly_context ctx;

  if (kl != CHACHAPOLY_KEY_LEN) {
    return luaL_error(L, "key must be 32 bytes, got %d", (int)kl);
  }

  size_t overhead = CHACHAPOLY_NONCE_LEN + CHACHAPOLY_TAG_LEN;
  if (dl < overhead) {
    lua_pushnil(L);
    lua_pushstring(L, "ciphertext too short");
    return 2;
  }

  const unsigned char *nonce = (const unsigned char *)data;
  const unsigned char *tag = (const unsigned char *)data + CHACHAPOLY_NONCE_LEN;
  const unsigned char *ct = (const unsigned char *)data + overhead;
  size_t ct_len = dl - overhead;

  /* allocate output buffer */
  uint8_t *plaintext = lua_newuserdata(L, ct_len > 0 ? ct_len : 1);

  mbedtls_chachapoly_init(&ctx);
  rc = mbedtls_chachapoly_setkey(&ctx, (const unsigned char *)key);
  if (rc != 0) {
    mbedtls_chachapoly_free(&ctx);
    lua_pushnil(L);
    lua_pushstring(L, "failed to set key");
    return 2;
  }

  rc = mbedtls_chachapoly_auth_decrypt(&ctx,
      ct_len,
      nonce,
      (const unsigned char *)aad, al,
      tag,
      ct,
      plaintext);

  mbedtls_chachapoly_free(&ctx);

  if (rc == MBEDTLS_ERR_CHACHAPOLY_AUTH_FAILED) {
    lua_pushnil(L);
    lua_pushstring(L, "authentication failed");
    return 2;
  }
  if (rc != 0) {
    lua_pushnil(L);
    lua_pushstring(L, "decryption failed");
    return 2;
  }

  lua_pushlstring(L, (const char *)plaintext, ct_len);
  return 1;
}

/**
 * Hkdf(ikm, salt, info[, length]) → okm
 *
 * Derives a key using HKDF-SHA256 (RFC 5869).
 *
 * @param ikm    input keying material (raw bytes)
 * @param salt   salt value (raw bytes, can be empty string)
 * @param info   context/application info (raw bytes, can be empty string)
 * @param length desired output length in bytes (default 32, max 8160)
 * @return derived key material on success
 * @return nil, error on failure
 */
int LuaHkdf(lua_State *L) {
  size_t ikm_len, salt_len, info_len;
  const char *ikm = luaL_checklstring(L, 1, &ikm_len);
  const char *salt = luaL_checklstring(L, 2, &salt_len);
  const char *info = luaL_checklstring(L, 3, &info_len);
  lua_Integer okm_len = luaL_optinteger(L, 4, 32);

  if (okm_len < 1 || okm_len > 255 * 32) {
    return luaL_error(L, "output length must be 1-%d, got %d",
                      255 * 32, (int)okm_len);
  }

  const mbedtls_md_info_t *md = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
  if (!md) {
    lua_pushnil(L);
    lua_pushstring(L, "SHA-256 not available");
    return 2;
  }

  uint8_t *okm = lua_newuserdata(L, okm_len);

  int rc = mbedtls_hkdf(md,
      (const unsigned char *)salt, salt_len,
      (const unsigned char *)ikm, ikm_len,
      (const unsigned char *)info, info_len,
      okm, okm_len);

  if (rc != 0) {
    lua_pushnil(L);
    lua_pushfstring(L, "HKDF failed (error %d)", rc);
    return 2;
  }

  lua_pushlstring(L, (const char *)okm, okm_len);
  return 1;
}
