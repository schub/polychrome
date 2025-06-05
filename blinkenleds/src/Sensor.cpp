#include <Arduino.h>
#include <Sensor.h>
#include <Network.h>

// PINS
#define TRIG1_PIN 14
#define TRIG2_PIN 33

#define ECHO1_PIN 34
#define ECHO2_PIN 35

// PWM TRIGGER
#define TRIGGER_FREQ_HZ 50

// ECHO MEASUREMENT
static unsigned long echoStartTime = 0;
static unsigned long echoEndTime = 0;
static bool measurementReady = false;

// READINGS PER SECOND
static unsigned long readingCount = 0;
static unsigned long lastRateCalculationTime = 0;
static float currentReadingsPerSecond = 0.0;

// Echo interrupt
void IRAM_ATTR echoISR()
{
  if (digitalRead(ECHO1_PIN) == HIGH)
  {
    echoStartTime = micros();
    measurementReady = false;
  }
  else
  {
    echoEndTime = micros();
    measurementReady = true;
  }
}

void Sensor::setup()
{
  pinMode(TRIG1_PIN, OUTPUT);
  pinMode(TRIG2_PIN, OUTPUT);
  pinMode(ECHO1_PIN, INPUT);
  pinMode(ECHO2_PIN, INPUT);

  // PWM for trigger
  ledcSetup(0, TRIGGER_FREQ_HZ, 16);
  ledcAttachPin(TRIG1_PIN, 0);
  ledcWrite(0, 13); // duty value: 13 steps = 13/2^16 =~ 20µs pulse duration (high time)

  // Interrupt for echo
  attachInterrupt(digitalPinToInterrupt(ECHO1_PIN), echoISR, CHANGE);

  Serial.println("Sensor setup done, frequency: " + String(TRIGGER_FREQ_HZ) + "Hz");
}

void Sensor::loop()
{
  if (measurementReady)
  {
    unsigned long duration = echoEndTime - echoStartTime;
    float distance = duration * 0.034 / 2;

    Network::send_sensor_event(0, distance);

    readingCount++;

    unsigned long currentTime = millis();
    if (currentTime - lastRateCalculationTime >= 1000)
    {
      float timeInterval = (currentTime - lastRateCalculationTime) / 1000.0;
      currentReadingsPerSecond = readingCount / timeInterval;
      readingCount = 0;
      lastRateCalculationTime = currentTime;
    }

    measurementReady = false;
  }
  else
  {
    // Serial.println("Measurement not ready");
  }
}

float Sensor::getReadingsPerSecond()
{
  return currentReadingsPerSecond;
}