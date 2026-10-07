/* roman.c: see roman.h. */
#include <string.h>

#include "roman.h"

/* Mac Roman 0x80-0xFF as Unicode */
static const unsigned short kRoman[128] = {
	0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1,  /* 80 */
	0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,  /* 88 */
	0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3,  /* 90 */
	0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,  /* 98 */
	0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF,  /* A0 */
	0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,  /* A8 */
	0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211,  /* B0 */
	0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,  /* B8 */
	0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB,  /* C0 */
	0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,  /* C8 */
	0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA,  /* D0 */
	0x00FF, 0x0178, 0x2044, 0x00A4, 0x2039, 0x203A, 0xFB01, 0xFB02,  /* D8 */
	0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1,  /* E0 */
	0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,  /* E8 */
	0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC,  /* F0 */
	0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7   /* F8 */
};

/* Latin Extended-A (U+0100-U+017F) folded to base letters */
static const char kLatinA[] =
	"AaAaAaCcCcCcCcDd" "DdEeEeEeEeEeGgGg" "GgGgHhHhIiIiIiIi" "IiIiJjKkkLlLlLlL"
	"lLlNnNnNnnNnOoOo" "OoOoRrRrRrSsSsSs" "SsTtTtTtUuUuUuUu" "UuUuWwYyYZzZzZzs";

unsigned char roman_from_cp(unsigned long cp)
{
	int i;

	if (cp < 0x80)
		return (unsigned char) cp;
	for (i = 0; i < 128; i++)
		if (kRoman[i] == cp)
			return (unsigned char) (0x80 + i);
	if (cp >= 0x100 && cp <= 0x17F)
		return (unsigned char) kLatinA[cp - 0x100];
	switch (cp) {
	case 0x00D0: return 'D';                    /* Eth */
	case 0x00F0: return 'd';
	case 0x00DD: return 'Y';
	case 0x00FD: return 'y';
	case 0x00DE: return 'T';                    /* Thorn */
	case 0x00FE: return 't';
	case 0x00D7: return 'x';                    /* multiplication sign */
	case 0x00AD: return '-';                    /* soft hyphen */
	case 0x00B2: return '2';
	case 0x00B3: return '3';
	case 0x00B9: return '1';
	case 0x20AC: return 0xDB;                   /* euro: the currency sign */
	case 0x2010: case 0x2011: case 0x2012: case 0x2015: case 0x2212: return '-';
	case 0x2032: return '\'';
	case 0x2033: return '"';
	case 0x2028: case 0x2029: return ' ';
	case 0x200B: case 0x200C: case 0x200D: case 0xFEFF: return 0;   /* zero width: dropped */
	}
	if (cp >= 0x2000 && cp <= 0x200A)            /* the typographic spaces */
		return ' ';
	return '?';
}

long roman_from_utf8(char *s)
{
	unsigned char *in = (unsigned char *) s, *out = (unsigned char *) s;
	unsigned long cp;
	int extra, k;

	while (*in) {
		unsigned char c = *in;
		if (c < 0x80) {
			*out++ = *in++;
			continue;
		}
		extra = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : -1;
		in++;
		if (extra < 0) {
			*out++ = '?';
			continue;
		}
		cp = c & (0x3F >> extra);
		for (k = 0; k < extra; k++) {
			if ((*in & 0xC0) != 0x80)
				break;
			cp = (cp << 6) | (*in++ & 0x3F);
		}
		if (k < extra) {
			*out++ = '?';
			continue;
		}
		c = roman_from_cp(cp);
		if (c != 0)
			*out++ = c;
	}
	*out = '\0';
	return (long) (out - (unsigned char *) s);
}

int roman_to_utf8(const char *in, char *out, long cap)
{
	long n = 0;
	const unsigned char *p = (const unsigned char *) in;

	for (; *p; p++) {
		unsigned long cp = *p < 0x80 ? *p : kRoman[*p - 0x80];
		int len = cp < 0x80 ? 1 : cp < 0x800 ? 2 : 3;
		if (n + len >= cap) {
			out[n] = '\0';
			return 0;
		}
		if (len == 1) {
			out[n++] = (char) cp;
		} else if (len == 2) {
			out[n++] = (char) (0xC0 | (cp >> 6));
			out[n++] = (char) (0x80 | (cp & 0x3F));
		} else {
			out[n++] = (char) (0xE0 | (cp >> 12));
			out[n++] = (char) (0x80 | ((cp >> 6) & 0x3F));
			out[n++] = (char) (0x80 | (cp & 0x3F));
		}
	}
	out[n] = '\0';
	return 1;
}
