#include <Arduino.h>
#include <schema.pb.h>
#include <Display.h>
#include <Network.h>
#include <Sensor.h>

void setup()
{
  Serial.begin(115200);
  while (!Serial)
    ; // wait for serial attach

  Serial.println("Initializing...");
  Serial.flush();

  delay(50);

  Display::setup();
  Network::setup();
  Sensor::setup();

  Serial.println("Setup done");
}

void loop()
{
  Network::loop();
  Display::loop();
  Sensor::loop();
}
