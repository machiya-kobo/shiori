/*
 * roman.h: UTF-8 and Mac OS Roman, the classic Mac's character set.
 * The table is Apple's published mapping, with 0xDB as the currency sign
 * (U+00A4), as System 6 and 7's fonts draw it (the euro came with Mac OS
 * 8.5). Characters Mac Roman lacks fall back to a base Latin letter
 * ("ō" -> "o"), a close ASCII form ("…" is there; "‐" -> "-"), or '?'.
 * Bytes below 0x80 (the snippet's mark bytes included) pass unchanged.
 */
#ifndef SHIORI_ROMAN_H
#define SHIORI_ROMAN_H

/* UTF-8 to Mac Roman, in place (never longer); returns the new length. */
long roman_from_utf8(char *s);
/* Mac Roman to UTF-8 into out (NUL-terminated); 0 when it didn't fit. */
int roman_to_utf8(const char *in, char *out, long cap);
/* One code point as Mac Roman ('?' when it has no form). */
unsigned char roman_from_cp(unsigned long cp);

#endif
