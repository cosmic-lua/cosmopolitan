#include "simdjson.h"
#include <cstdio>
int main() {
  simdjson::ondemand::parser parser;
  auto json = simdjson::padded_string::load("/dev/stdin");
  simdjson::ondemand::document doc = parser.iterate(json);
  std::string_view name;
  auto err = doc["name"].get(name);
  if (err) { printf("error: %s\n", simdjson::error_message(err)); return 1; }
  printf("name = %.*s\n", (int)name.size(), name.data());
  return 0;
}
