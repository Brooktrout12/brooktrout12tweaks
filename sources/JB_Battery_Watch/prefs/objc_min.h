#ifndef JBBW_OBJC_MIN_H
#define JBBW_OBJC_MIN_H
/* Narrow, original declarations for stable Objective-C runtime/Foundation/UIKit
 * interfaces. No SDK implementation or framework binary is included. */
#include "../src/platform.h"
#include <stdbool.h>
typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void (*IMP)(void);
typedef struct { double x,y; } CGPoint;
typedef struct { double width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
struct objc_super { id receiver; Class super_class; };
extern Class objc_getClass(const char *);
extern Class objc_allocateClassPair(Class,const char *,size_t);
extern void objc_registerClassPair(Class);
extern bool class_addMethod(Class,SEL,IMP,const char *);
extern SEL sel_registerName(const char *);
extern id objc_getAssociatedObject(id,const void *);
extern void objc_setAssociatedObject(id,const void *,id,unsigned long);
extern void objc_msgSend(void);
extern void objc_msgSendSuper2(void);
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *);
extern id NSTemporaryDirectory(void);
extern int notify_register_check(const char *,int *);
extern int notify_set_state(int,uint64_t);
extern int notify_post(const char *);
extern int notify_cancel(int);
extern uint32_t arc4random(void);
extern char *strerror(int);
extern int libSandy_applyProfile(const char *);
static inline SEL S(const char *s){return sel_registerName(s);}
static inline id C(const char *s){return (id)objc_getClass(s);}
static inline id M0(id o,const char *s){return ((id(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline id M1(id o,const char *s,id a){return ((id(*)(id,SEL,id))objc_msgSend)(o,S(s),a);}
static inline id M2(id o,const char *s,id a,id b){return ((id(*)(id,SEL,id,id))objc_msgSend)(o,S(s),a,b);}
static inline void V0(id o,const char *s){((void(*)(id,SEL))objc_msgSend)(o,S(s));}
static inline void V1(id o,const char *s,id a){((void(*)(id,SEL,id))objc_msgSend)(o,S(s),a);}
static inline void V2(id o,const char *s,id a,id b){((void(*)(id,SEL,id,id))objc_msgSend)(o,S(s),a,b);}
static inline id N(const char *s){return ((id(*)(id,SEL,const char*))objc_msgSend)(C("NSString"),S("stringWithUTF8String:"),s?s:"");}
static inline const char *U(id o){return o?((const char*(*)(id,SEL))objc_msgSend)(o,S("UTF8String")):0;}
static inline long long I(id o){return o?((long long(*)(id,SEL))objc_msgSend)(o,S("longLongValue")):0;}
static inline double F(id o){return o?((double(*)(id,SEL))objc_msgSend)(o,S("doubleValue")):0;}
static inline bool B(id o){return o?((bool(*)(id,SEL))objc_msgSend)(o,S("boolValue")):false;}
static inline id number(long long n){return ((id(*)(id,SEL,long long))objc_msgSend)(C("NSNumber"),S("numberWithLongLong:"),n);}
static inline id get(id d,const char *k){return M1(d,"objectForKey:",N(k));}
static inline void put(id d,const char *k,id v){if(v)V2(d,"setObject:forKey:",v,N(k));}
static inline bool iskind(id o,const char *cls){return o&&((bool(*)(id,SEL,Class))objc_msgSend)(o,S("isKindOfClass:"),objc_getClass(cls));}
#endif
