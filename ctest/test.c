#ifndef ABC
#  include <stdlib.h> 
#  include <stdio.h> 
#  define ABD \
	xyz
#define xyz 
#define abc(x,y,z) blah
#define abcd(x,y,z) blah \
	foo(y)
#endif

#include <signal.h> 
#  define ABD1 \
	xyz
#define xyz1 
#define abc1(x,y,z) blah
#define abcd1(x,y,z) blah \
	foo(y)

__inline__ int inline_func(int i) { return i++; }
#define FOO_NAME(bar)((BAZ*) fooBAR(bar))->baz
extern double atofoo (__const char *__fooptr);
extern int extern_func(int i);
extern int myarray[56];
extern int myfunc(int myarrayarg[56]);
extern int (*myfuncp[45])(int arrayarg[56]);
