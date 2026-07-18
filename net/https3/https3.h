#ifndef COSMOPOLITAN_NET_HTTPS3_HTTPS3_H_
#define COSMOPOLITAN_NET_HTTPS3_HTTPS3_H_
#include "third_party/mbedtls3/include/mbedtls/ctr_drbg.h"
#include "third_party/mbedtls3/include/mbedtls/x509_crt.h"
#ifdef __cplusplus
extern "C" {
#endif

/* the Mbed TLS 3.6 counterpart of the net/https support functions the
   lua binary needs; symbol names match net/https so consumers only
   change which package they link. never link both into one binary. */

char *GetTlsError(int);
char *DescribeSslVerifyFailure(int);
mbedtls_x509_crt *GetSslRoots(void);
void InitializeRng(mbedtls_ctr_drbg_context *);
int GetEntropy(void *, unsigned char *, size_t);

#ifdef __cplusplus
}
#endif
#endif /* COSMOPOLITAN_NET_HTTPS3_HTTPS3_H_ */
