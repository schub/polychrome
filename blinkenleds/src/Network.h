#ifndef __NETWORK_H_INCLUDED__
#define __NETWORK_H_INCLUDED__

class Network
{

public:
  static void setup();
  static void loop();
  static void remote_log(String message);
  static void send_firmware_info();
  static void send_sensor_event(uint32_t sensor_index, float distance);

private:
};

#endif // __NETWORK_H_INCLUDED__
