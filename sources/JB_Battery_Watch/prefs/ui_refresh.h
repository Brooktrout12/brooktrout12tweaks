#ifndef JBBW_UI_REFRESH_H
#define JBBW_UI_REFRESH_H
#include "objc_min.h"
/* 0: no safe refresh path; 1: PSListController reloadSpecifiers;
 * 2: verified table getter; 3: verified already-loaded root table view. */
int jbbw_refresh_list(id controller);
#endif
