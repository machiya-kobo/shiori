/*
 * draw.h: text drawing for 1-bit QuickDraw on a 512×342 screen: strings cut
 * to a width with an ellipsis, and snippets whose marked words are bold.
 * Text here is Mac Roman (core/roman.c converts).
 */
#ifndef SHIORI_DRAW_H
#define SHIORI_DRAW_H

#include <Quickdraw.h>

/* Draws s (C string) at the pen, cut to maxWidth pixels with "…". */
void DrawFitted(const char *s, short maxWidth);
/* The number of bytes of s that fit in maxWidth with an ellipsis after them
   (all of it when it fits whole). */
short FitLength(const char *s, short len, short maxWidth, Boolean *cut);
/* Draws a snippet (SNIPPET_MARK_ON/OFF bytes around marked words) on one line,
   marked words bold, cut to maxWidth with "…". */
void DrawSnippet(const char *s, short maxWidth);
/* Draws a C string at the pen. */
void DrawC(const char *s);

#endif
