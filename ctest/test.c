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

__inline__ int func(int i) { return i++; }