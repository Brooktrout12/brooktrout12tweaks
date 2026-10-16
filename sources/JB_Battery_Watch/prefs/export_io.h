#ifndef JBBW_EXPORT_IO_H
#define JBBW_EXPORT_IO_H
#include "../src/platform.h"
/* Only six recorder-owned diagnostic filenames are exportable. */
int jbbw_append_diagnostic(FILE *out,const char *directory,const char *name,long cap);
#endif
