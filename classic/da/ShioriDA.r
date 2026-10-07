/* The desk accessory as a 'DRVR' resource; its name starts with a NUL, as a DA's does. */
data 'DRVR' (26, "\0x00Shiori Search", purgeable) { $$read("ShioriDA.flt") };
