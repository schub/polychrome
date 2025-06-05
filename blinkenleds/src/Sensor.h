#ifndef __SENSOR_H_INCLUDED__
#define __SENSOR_H_INCLUDED__

#include <Pixel.h>
#include <schema.pb.h>

class Sensor
{
public:
  static void setup();
  static void loop();
  static float getReadingsPerSecond();
};

#endif // __SENSOR_H_INCLUDED__
