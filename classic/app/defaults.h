/*
 * defaults.h: the bridge and the Mac's room token until Preferences has them,
 * for the app and the desk accessory alike. Builds take them from
 * classic/local.env (gitignored); these neutral defaults reach nothing.
 */
#ifndef SHIORI_DEFAULTS_H
#define SHIORI_DEFAULTS_H

#ifndef SHIORI_DEFAULT_HISTER
#define SHIORI_DEFAULT_HISTER "http://192.0.2.1:8070/"
#endif
#ifndef SHIORI_DEFAULT_KURA
#define SHIORI_DEFAULT_KURA "http://192.0.2.1:8071/"
#endif
#ifndef SHIORI_DEFAULT_TOKEN
#define SHIORI_DEFAULT_TOKEN ""
#endif

#endif
