/*-*- mode:c;indent-tabs-mode:t;c-basic-offset:8;tab-width:8;coding:utf-8   -*-│
│ vi: set et ft=c ts=8 sw=8 fenc=utf-8                                     :vi │
╚──────────────────────────────────────────────────────────────────────────────╝
│                                                                              │
│  largon2                                                                     │
│  Copyright © 2016 Thibault Charbonnier                                       │
│                                                                              │
│  Permission is hereby granted, free of charge, to any person obtaining       │
│  a copy of this software and associated documentation files (the             │
│  "Software"), to deal in the Software without restriction, including         │
│  without limitation the rights to use, copy, modify, merge, publish,         │
│  distribute, sublicense, and/or sell copies of the Software, and to          │
│  permit persons to whom the Software is furnished to do so, subject to       │
│  the following conditions:                                                   │
│                                                                              │
│  The above copyright notice and this permission notice shall be              │
│  included in all copies or substantial portions of the Software.             │
│                                                                              │
│  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,             │
│  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF          │
│  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.      │
│  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY        │
│  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,        │
│  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE           │
│  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                      │
│                                                                              │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/bsdstdlib.h"
#include "libc/isystem/stdio.h"
#include "libc/isystem/string.h"
#include "third_party/argon2/argon2.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"
#include "third_party/lua/lualib.h"

__notice(largon2_notice, "\
largon2 (MIT License)\n\
Copyright 2016 Thibault Charbonnier");

// clang-format off
/***
Lua C binding for the Argon2 password hashing function.

See the [Argon2 documentation](https://github.com/P-H-C/phc-winner-argon2)
for in-depth instructions and details about Argon2.

@module argon2
@author Thibault Charbonnier
@license MIT
*/


/***
Argon2 hashing options. These options can be given to `hash_encoded` as a
table. If values are omitted, the module defaults are used.
@field t_cost Number of iterations (`number`, default: `3`).
@field m_cost Memory usage in KiB (`number`, default: `4096`).
@field parallelism Number of threads and compute lanes (`number`, default: `1`).
@field hash_len Length of the raw hash output in bytes (`number`, default: `32`).
@field variant Argon2 variant to use, one of the strings "argon2id" (default),
"argon2i", or "argon2d".
@table options
*/
#define LUA_ARGON2_DEFAULT_T_COST 3
#define LUA_ARGON2_DEFAULT_M_COST 4096
#define LUA_ARGON2_DEFAULT_PARALLELISM 1
#define LUA_ARGON2_DEFAULT_HASH_LEN 32
#define LUA_ARGON2_SALT_LEN 16


static void
largon2_integer_opt(lua_State *L, int optidx, int argidx,
                    uint32_t *property, const char *key)
{
    char            errmsg[64];

    if (!lua_isnil(L, optidx)) {
        if (lua_isnumber(L, optidx)) {
            *property = (uint32_t) lua_tonumber(L, optidx);

        } else {
            sprintf(errmsg, "expected %s to be a number, got %s",
                    key, luaL_typename(L, optidx));
            luaL_argerror(L, argidx, errmsg);
        }
    }
}


/* BINDINGS */


/***
Hashes a password with Argon2i, Argon2d, or Argon2id, producing an encoded
hash.
@function hash_encoded
@param[type=string] plain Plain string to hash.
@param[type=string] salt Salt to use. Optional: if nil or omitted, 16 random
bytes are generated with a CSPRNG.
@param[type=table] options Options with which to hash the plain string. See
`options`. Optional; omitted values use the module defaults.
@treturn string `encoded`: Encoded hash computed by Argon2, or `nil` on error.
@treturn string `err`: `nil`, or a string describing the error if any.

@usage
local hash, err = argon2.hash_encoded("password")   -- random salt
if not hash then error("could not hash: " .. err) end

-- with an explicit salt, options, and variant
local hash, err = argon2.hash_encoded("password", "somesalt", {
  t_cost = 4,
  m_cost = 1 << 16, -- 65536 KiB
  variant = "argon2id",
})
*/
static int
largon2_hash_encoded(lua_State *L)
{
    const char             *plain, *salt;
    char                   *encoded, *err_msg;
    size_t                  plainlen, saltlen;
    size_t                  encoded_len;
    uint32_t                t_cost      = LUA_ARGON2_DEFAULT_T_COST;
    uint32_t                m_cost      = LUA_ARGON2_DEFAULT_M_COST;
    uint32_t                parallelism = LUA_ARGON2_DEFAULT_PARALLELISM;
    uint32_t                hash_len    = LUA_ARGON2_DEFAULT_HASH_LEN;
    argon2_type             variant     = Argon2_id;
    argon2_error_codes      ret_code;
    luaL_Buffer             buf;
    uint8_t                 saltbuf[LUA_ARGON2_SALT_LEN];

    plain = luaL_checklstring(L, 1, &plainlen);

    if (lua_isnoneornil(L, 2)) {
        arc4random_buf(saltbuf, sizeof(saltbuf));
        salt    = (const char *) saltbuf;
        saltlen = sizeof(saltbuf);
    } else {
        salt = luaL_checklstring(L, 2, &saltlen);
    }

    if (!lua_isnoneornil(L, 3)) {
        luaL_checktype(L, 3, LUA_TTABLE);

        lua_getfield(L, 3, "t_cost");
        largon2_integer_opt(L, -1, 3, &t_cost, "t_cost");
        lua_pop(L, 1);

        lua_getfield(L, 3, "m_cost");
        largon2_integer_opt(L, -1, 3, &m_cost, "m_cost");
        lua_pop(L, 1);

        lua_getfield(L, 3, "parallelism");
        largon2_integer_opt(L, -1, 3, &parallelism, "parallelism");
        lua_pop(L, 1);

        lua_getfield(L, 3, "hash_len");
        largon2_integer_opt(L, -1, 3, &hash_len, "hash_len");
        lua_pop(L, 1);

        lua_getfield(L, 3, "variant");
        if (!lua_isnil(L, -1)) {
            const char *vs;
            if (lua_type(L, -1) != LUA_TSTRING) {
                luaL_argerror(L, 3, lua_pushfstring(L,
                    "expected variant to be a string, got %s",
                    luaL_typename(L, -1)));
            }
            vs = lua_tostring(L, -1);
            if (!strcmp(vs, "argon2id")) {
                variant = Argon2_id;
            } else if (!strcmp(vs, "argon2i")) {
                variant = Argon2_i;
            } else if (!strcmp(vs, "argon2d")) {
                variant = Argon2_d;
            } else {
                luaL_argerror(L, 3, lua_pushfstring(L,
                    "unknown argon2 variant '%s' (want \"argon2id\", "
                    "\"argon2i\", or \"argon2d\")", vs));
            }
        }
        lua_pop(L, 1);
    }

    encoded_len = argon2_encodedlen(t_cost, m_cost, parallelism, saltlen,
                                    hash_len, variant);

    encoded = luaL_buffinitsize(L, &buf, encoded_len);

    if (variant == Argon2_d) {
        ret_code =
          argon2d_hash_encoded(t_cost, m_cost, parallelism, plain, plainlen,
                               salt, saltlen, hash_len, encoded, encoded_len);

    } else if (variant == Argon2_id) {
        ret_code =
          argon2id_hash_encoded(t_cost, m_cost, parallelism, plain, plainlen,
                                salt, saltlen, hash_len, encoded, encoded_len);

    } else {
        ret_code =
          argon2i_hash_encoded(t_cost, m_cost, parallelism, plain, plainlen,
                               salt, saltlen, hash_len, encoded, encoded_len);
    }

    luaL_pushresultsize(&buf, encoded_len - 1);

    if (ret_code != ARGON2_OK) {
        err_msg = (char *) argon2_error_message(ret_code);
        lua_pushnil(L);
        lua_pushstring(L, err_msg);
        return 2;
    }

    return 1;
}


/***
Verifies a password against an encoded string.
@function verify
@param[type=string] encoded Encoded string to verify the plain password against.
@param[type=string] password Plain password to verify.
@treturn boolean `ok`: `true` if the password matches, `false` otherwise (both a
mismatch and a malformed encoded string yield `false`).
@treturn string `err`: `nil` on match or plain mismatch; a string describing the
error when the encoded string is malformed.

@usage
local ok, err = argon2.verify(encoded, "password")
if err then
  -- malformed encoded hash (*not* a mismatch)
  error("could not verify: " .. err)
elseif not ok then
  -- password mismatch
  error("the password does not match the supplied hash")
end
*/
static int
largon2_verify(lua_State *L)
{
    const char             *plain, *encoded;
    size_t                  plainlen;
    argon2_type             variant;
    argon2_error_codes      ret_code;
    char                   *err_msg;

    encoded = luaL_checkstring(L, 1);
    plain   = luaL_checklstring(L, 2, &plainlen);

    if (strstr(encoded, "argon2d")) {
        variant = Argon2_d;

    } else if (strstr(encoded, "argon2id")) {
        variant = Argon2_id;

    } else {
        variant = Argon2_i;
    }

    ret_code = argon2_verify(encoded, plain, plainlen, variant);
    if (ret_code == ARGON2_OK) {
        lua_pushboolean(L, 1);
        return 1;
    }

    if (ret_code == ARGON2_VERIFY_MISMATCH) {
        lua_pushboolean(L, 0);
        return 1;
    }

    /* malformed encoded string, bad parameters, etc. */
    err_msg = (char *) argon2_error_message(ret_code);
    lua_pushboolean(L, 0);
    lua_pushstring(L, err_msg);
    return 2;
}


/* MODULE */


static const luaL_Reg largon2[] = { { "verify", largon2_verify },
                                    { "hash_encoded", largon2_hash_encoded },
                                    { NULL, NULL } };


int
luaopen_argon2(lua_State *L)
{
    luaL_newlib(L, largon2);

    lua_pushliteral(L, "3.0.1");
    lua_setfield(L, -2, "_VERSION");

    lua_pushliteral(L, "Thibault Charbonnier");
    lua_setfield(L, -2, "_AUTHOR");

    lua_pushliteral(L, "MIT");
    lua_setfield(L, -2, "_LICENSE");

    lua_pushliteral(L, "https://github.com/thibaultcha/lua-argon2");
    lua_setfield(L, -2, "_URL");

    return 1;
}
