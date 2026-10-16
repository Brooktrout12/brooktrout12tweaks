#ifndef JBBW_INVENTORY_H
#define JBBW_INVENTORY_H
#include "darwin.h"
void inventory(FILE *f,int initialize);
const char *file_owner(const char *path);
void report_candidates(FILE *f,const Total *t);
void inventory_free(void);
#endif
