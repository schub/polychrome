#include <Arduino.h>
#include <schema.pb.h>
#include <Display.h>
#include <Network.h>
#include <Proximity.h>

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
  Proximity::setup();

  Serial.println("Setup done");
}

void loop()
{
  Network::loop();
  Display::loop();
  Proximity::loop();
}
