#include "simdjson.h"
#include <cstdio>
int main() {
  printf("active implementation: %s (%s)\n",
         simdjson::get_active_implementation()->name().data(),
         simdjson::get_active_implementation()->description().data());
  return 0;
}
