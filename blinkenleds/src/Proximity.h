#ifndef __PROXIMITY_H_INCLUDED__
#define __PROXIMITY_H_INCLUDED__

#include <Pixel.h>
#include <schema.pb.h>

class Proximity
{
public:
  static void setup();
  static void loop();
  static float getReadingsPerSecond();
};

#endif // __PROXIMITY_H_INCLUDED__
